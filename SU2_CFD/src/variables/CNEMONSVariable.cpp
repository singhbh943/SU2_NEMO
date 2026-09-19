/*!
 * \file CNEMONSVariable.cpp
 * \brief Definition of the solution fields.
 * \author C. Garbacz, W. Maier, S.R. Copeland
 * \version 8.5.0 "Harrier"
 *
 * SU2 Project Website: https://su2code.github.io
 *
 * The SU2 Project is maintained by the SU2 Foundation
 * (http://su2foundation.org)
 *
 * Copyright 2012-2026, SU2 Contributors (cf. AUTHORS.md)
 *
 * SU2 is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * SU2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with SU2. If not, see <http://www.gnu.org/licenses/>.
 */

#include "../../include/variables/CNEMONSVariable.hpp"
#include <cmath>

CNEMONSVariable::CNEMONSVariable(su2double val_pressure,
                                 const su2double *val_massfrac,
                                 const su2double *val_mach,
                                 su2double val_temperature,
                                 su2double val_temperature_ve,
                                 unsigned long npoint,
                                 unsigned long val_ndim,
                                 unsigned long val_nvar,
                                 unsigned long val_nvarprim,
                                 unsigned long val_nvarprimgrad,
                                 const CConfig *config,
                                 CNEMOGas *fluidmodel) : CNEMOEulerVariable(val_pressure,
                                                                       val_massfrac,
                                                                       val_mach,
                                                                       val_temperature,
                                                                       val_temperature_ve,
                                                                       npoint,
                                                                       val_ndim,
                                                                       val_nvar,
                                                                       val_nvarprim,
                                                                       val_nvarprimgrad,
                                                                       config,
                                                                       fluidmodel) {

  Temperature_Ref = config->GetTemperature_Ref();
  Viscosity_Ref   = config->GetViscosity_Ref();
  Viscosity_Inf   = config->GetViscosity_FreeStreamND();
  Prandtl_Lam     = config->GetPrandtl_Lam();

  DiffusionCoeff.resize(nPoint, nSpecies)  = su2double(0.0);
  LaminarViscosity.resize(nPoint)          = su2double(0.0);
  ThermalCond.resize(nPoint)               = su2double(0.0);
  ThermalCond_ve.resize(nPoint)            = su2double(0.0);
  Enthalpys.resize(nPoint, nSpecies)       = su2double(0.0);

  Max_Lambda_Visc.resize(nPoint) = su2double(0.0);
  inv_TimeScale = config->GetModVel_FreeStream() / config->GetRefLength();

  Vorticity.resize(nPoint,3)     = su2double(0.0);
  StrainMag.resize(nPoint)       = su2double(0.0);
  Tau_Wall.resize(nPoint)        = su2double(-1.0);
  DES_LengthScale.resize(nPoint) = su2double(0.0);
  lesMode.resize(nPoint)        = su2double(0.0);
  Roe_Dissipation.resize(nPoint) = su2double(0.0);
  Vortex_Tilting.resize(nPoint)  = su2double(0.0);
  Max_Lambda_Visc.resize(nPoint) = su2double(0.0);

}

bool CNEMONSVariable::SetPrimVar(unsigned long iPoint, CFluidModel *FluidModel) {

  fluidmodel = static_cast<CNEMOGas*>(FluidModel);

  /*
   * Preserve the raw conservative candidate before Cons2PrimVar().
   * Cons2PrimVar may modify species densities in-place, so all
   * backtracking trials must be reconstructed from this untouched
   * candidate.
   */
  su2double candidateState[MAXNVAR];

  for (auto iVar = 0u; iVar < nVar; ++iVar)
    candidateState[iVar] = Solution(iPoint,iVar);

  /*
   * Preserve the previous accepted vibrational-electronic temperature
   * as the nonlinear inversion seed.  A failed trial must not poison
   * the seed used by subsequent trials.
   */
  const su2double TSeed =
      Primitive(iPoint,T_INDEX);
  const su2double TveSeed =
      Primitive(iPoint,TVE_INDEX);

  /*
   * Cons2PrimVar()/Mutation++ temperature inversion modifies the
   * internal mixture state even when the candidate is subsequently
   * rejected.  Every independent recovery attempt therefore has to
   * begin from the same last thermochemically accepted state.
   *
   * In SetPrimVar() the recovery line is based on Solution_Accepted,
   * not on the possibly-invalid current Solution candidate.
   */
  std::vector<su2double> acceptedRhos(nSpecies, 0.0);
  for (unsigned short iSpecies = 0;
       iSpecies < nSpecies;
       ++iSpecies)
    acceptedRhos[iSpecies] =
        Solution_Accepted(iPoint,iSpecies);

  auto restoreAcceptedFluidState = [&]() {
    fluidmodel->SetTDStateRhosTTv(
        acceptedRhos,
        TSeed,
        TveSeed);
  };

  /*
   * First try the live conservative candidate directly.
   *
   * Do NOT restore Mutation++ before this conversion.  In particular,
   * immediately after restart loading the primitive T/Tve seed may not
   * yet represent the loaded conservative state.  Cons2PrimVar() must
   * reconstruct that state first.
   */
  const bool candidateNonPhys =
      Cons2PrimVar(
          Solution[iPoint],
          Primitive[iPoint],
          dPdU[iPoint],
          dTdU[iPoint],
          dTvedU[iPoint],
          eves[iPoint],
          Cvves[iPoint]);

  /*
   * Keep state validity separate from reporting.  A recovered/backtracked
   * state is admissible for continued computation, but the original
   * candidate must still be reported as nonphysical to the solver.
   */
  bool storedStateNonPhys = candidateNonPhys;

  /*
   * A thermochemically invalid candidate is locally backtracked toward
   * the last state that successfully completed conservative-to-primitive
   * recovery:
   *
   *   U_trial =
   *       U_accepted
   *       + alpha (U_candidate - U_accepted),
   *
   * alpha = 1/2, 1/4, 1/8, ...
   *
   * Solution_Old is intentionally not used here.  It remains SU2's
   * RK/time-integration buffer and is not guaranteed to be a
   * thermochemically accepted state.
   */
  if (candidateNonPhys) {

    bool recovered = false;
    su2double alpha = 0.5;

    constexpr unsigned short maxBacktrack = 16;

    for (unsigned short iTry = 0;
         iTry < maxBacktrack;
         ++iTry) {

      for (auto iVar = 0u;
           iVar < nVar;
           ++iVar) {

        Solution(iPoint,iVar) =
            Solution_Accepted(iPoint,iVar)
            + alpha
            * (candidateState[iVar]
               - Solution_Accepted(iPoint,iVar));
      }

      /*
       * Restore the complete accepted Mutation++ state before every
       * independent thermochemical recovery attempt.  Restoring only
       * Primitive[T,Tve] is insufficient because a failed inversion
       * also changes Mutation++'s internal mixture state.
       */
      restoreAcceptedFluidState();

      Primitive(iPoint,T_INDEX)   = TSeed;
      Primitive(iPoint,TVE_INDEX) = TveSeed;

      const bool trialNonPhys =
          Cons2PrimVar(
              Solution[iPoint],
              Primitive[iPoint],
              dPdU[iPoint],
              dTdU[iPoint],
              dTvedU[iPoint],
              eves[iPoint],
              Cvves[iPoint]);

      if (!trialNonPhys) {
        recovered = true;
        break;
      }

      alpha *= 0.5;
    }

    if (recovered) {

      storedStateNonPhys = false;

    } else {

      /*
       * No candidate on the backtracking line was admissible.
       * Restore the last state that was actually accepted by the
       * thermochemical conversion rather than Solution_Old.
       */
      for (auto iVar = 0u;
           iVar < nVar;
           ++iVar)
        Solution(iPoint,iVar) =
            Solution_Accepted(iPoint,iVar);

      restoreAcceptedFluidState();

      Primitive(iPoint,T_INDEX)   = TSeed;
      Primitive(iPoint,TVE_INDEX) = TveSeed;

      const bool acceptedNonPhys =
          Cons2PrimVar(
              Solution[iPoint],
              Primitive[iPoint],
              dPdU[iPoint],
              dTdU[iPoint],
              dTvedU[iPoint],
              eves[iPoint],
              Cvves[iPoint]);

      /*
       * This condition means the solver's fundamental invariant has
       * been violated: a state previously recorded as accepted can no
       * longer be converted.  Never allow such a state to continue to
       * gamma, transport properties, chemistry, vibrational relaxation,
       * diffusion, or axisymmetric source evaluation.
       */
      if (acceptedNonPhys) {

        std::cerr
            << "[NEMO_ACCEPTED_STATE_FAILURE]"
            << " point=" << iPoint
            << " rhoE_accepted="
            << Solution_Accepted(iPoint,nSpecies+nDim)
            << " rhoEve_accepted="
            << Solution_Accepted(iPoint,nSpecies+nDim+1)
            << " T=" << Primitive(iPoint,T_INDEX)
            << " Tve=" << Primitive(iPoint,TVE_INDEX)
            << std::endl;

        SU2_MPI::Error(
            "NEMO last-accepted thermochemical state failed "
            "conservative-to-primitive recovery.",
            CURRENT_FUNCTION);
      }

      /*
       * The restored state passed conversion, so the point ultimately
       * stored by this routine is physical even though the original
       * candidate was not.
       */
      storedStateNonPhys = false;
    }
  }

  /*
   * Update the persistent accepted conservative state only after a
   * successful thermochemical conversion.  On the ordinary valid path
   * this is only a copy and does not modify Solution or Primitive.
   */
  if (!storedStateNonPhys) {
    for (auto iVar = 0u; iVar < nVar; ++iVar)
      Solution_Accepted(iPoint,iVar) = Solution(iPoint,iVar);
  }

  /*--- Set additional point quantities ---*/
  Gamma(iPoint) = fluidmodel->ComputeGamma();

  SetVelocity2(iPoint);

  const auto& Ds = fluidmodel->GetDiffusionCoeff();
  for (auto iSpecies = 0u; iSpecies < nSpecies; iSpecies++)
    DiffusionCoeff(iPoint, iSpecies) = Ds[iSpecies];

  su2double T   =  Primitive(iPoint,nSpecies);
  su2double Tve =  Primitive(iPoint,nSpecies+1);

  su2double* val_eves = GetEve(iPoint);
  const auto& hs = fluidmodel->ComputeSpeciesEnthalpy(T, Tve, val_eves);
  for (auto iSpecies = 0u; iSpecies < nSpecies; iSpecies++)
    Enthalpys(iPoint, iSpecies) = hs[iSpecies];

  LaminarViscosity(iPoint) = fluidmodel->GetViscosity();

  const auto& thermalconductivities = fluidmodel->GetThermalConductivities();
  ThermalCond(iPoint)      = thermalconductivities[0];
  ThermalCond_ve(iPoint)   = thermalconductivities[1];

  Primitive(iPoint, LAM_VISC_INDEX) = LaminarViscosity(iPoint);

  return candidateNonPhys;
}
