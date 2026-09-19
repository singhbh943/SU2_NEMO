/*!
 * \file CNEMOEulerVariable.cpp
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

#include "../../include/variables/CNEMOEulerVariable.hpp"
#include <cmath>

CNEMOEulerVariable::CNEMOEulerVariable(su2double val_pressure,
                                       const su2double *val_massfrac,
                                       const su2double *val_mach,
                                       su2double val_temperature,
                                       su2double val_temperature_ve,
                                       unsigned long npoint,
                                       unsigned long ndim,
                                       unsigned long nvar,
                                       unsigned long nvarprim,
                                       unsigned long nvarprimgrad,
                                       const CConfig *config,
                                       CNEMOGas *fluidmodel)
  : CFlowVariable(npoint, ndim, nvar, nvarprim, nvarprimgrad, config),
    indices(ndim, config->GetnSpecies()),
    implicit(config->GetKind_TimeIntScheme_Flow() == EULER_IMPLICIT) {

  unsigned short iDim, iSpecies;

  const bool dual_time = (config->GetTime_Marching() == TIME_MARCHING::DT_STEPPING_1ST) ||
                         (config->GetTime_Marching() == TIME_MARCHING::DT_STEPPING_2ND);
  const bool classical_rk4 = (config->GetKind_TimeIntScheme_Flow() == CLASSICAL_RK4_EXPLICIT);

  /*--- Setting variable amounts ---*/

  nSpecies        = config->GetnSpecies();
  RHOS_INDEX      = 0;
  T_INDEX         = nSpecies;
  TVE_INDEX       = nSpecies+1;
  VEL_INDEX       = nSpecies+2;
  P_INDEX         = nSpecies+nDim+2;
  RHO_INDEX       = nSpecies+nDim+3;
  H_INDEX         = nSpecies+nDim+4;
  A_INDEX         = nSpecies+nDim+5;
  RHOCVTR_INDEX   = nSpecies+nDim+6;
  RHOCVVE_INDEX   = nSpecies+nDim+7;
  LAM_VISC_INDEX  = nSpecies+nDim+8;
  EDDY_VISC_INDEX = nSpecies+nDim+9;

  /*--- Set monoatomic flag ---*/
  if (config->GetMonoatomic()) {
    monoatomic = true;
    Tve_Freestream = config->GetTemperature_ve_FreeStream();
  }

  /*--- Size Grad_AuxVar for axiysmmetric ---*/
  if (config->GetAxisymmetric()){
    nAuxVar = 3;
    Grad_AuxVar.resize(nPoint,nAuxVar,nDim,0.0);
    AuxVar.resize(nPoint,nAuxVar) = su2double(0.0);
  }

  /*--- Primitive and secondary variables ---*/
  Primitive_Aux.resize(nPoint,nPrimVar) = su2double(0.0);
  Secondary.resize(nPoint,nPrimVar) = su2double(0.0);

  dPdU.resize(nPoint, nVar)      = su2double(0.0);
  dTdU.resize(nPoint, nVar)      = su2double(0.0);
  dTvedU.resize(nPoint, nVar)    = su2double(0.0);
  Cvves.resize(nPoint, nSpecies)      = su2double(0.0);
  eves.resize(nPoint, nSpecies)       = su2double(0.0);
  Gamma.resize(nPoint)                = su2double(0.0);

  /*--- Set mixture state ---*/
  fluidmodel->SetTDStatePTTv(val_pressure, val_massfrac, val_temperature, val_temperature_ve);

  /*--- Compute necessary quantities ---*/
  const su2double rho = fluidmodel->GetDensity();
  const su2double soundspeed = fluidmodel->ComputeSoundSpeed();
  const su2double sqvel = GeometryToolbox::SquaredNorm(nDim, val_mach) * pow(soundspeed,2);
  const auto& energies = fluidmodel->ComputeMixtureEnergies();

  /*--- Loop over all points --*/
  for(unsigned long iPoint = 0; iPoint < nPoint; ++iPoint){

    /*--- Initialize Solution & Solution_Old vectors ---*/
    for (iSpecies = 0; iSpecies < nSpecies; iSpecies++)
      Solution(iPoint,iSpecies)     = rho*val_massfrac[iSpecies];
    for (iDim = 0; iDim < nDim; iDim++)
      Solution(iPoint,nSpecies+iDim)     = rho*val_mach[iDim]*soundspeed;

    Solution(iPoint,nSpecies+nDim)       = rho*(energies[0]+0.5*sqvel);
    Solution(iPoint,nSpecies+nDim+1)     = rho*(energies[1]);
  }

  Solution_Old = Solution;

  /*
   * The constructor state is generated directly from a thermodynamic
   * PT-Tve state and is therefore the initial last-known admissible
   * conservative state.
   */
  Solution_Accepted.resize(nPoint, nVar);
  Solution_Accepted = Solution;

  if (classical_rk4) Solution_New = Solution;

  /*--- Allocate and initializate solution for dual time strategy ---*/

  if (dual_time) {
    Solution_time_n = Solution;
    Solution_time_n1 = Solution;
  }

}

void CNEMOEulerVariable::SetVelocity2(unsigned long iPoint) {

  unsigned short iDim;

  Velocity2(iPoint) = 0.0;
  for (iDim = 0; iDim < nDim; iDim++) {
    Primitive(iPoint,VEL_INDEX+iDim) = Solution(iPoint,nSpecies+iDim) / Primitive(iPoint,RHO_INDEX);
    Velocity2(iPoint) +=  Solution(iPoint,nSpecies+iDim)*Solution(iPoint,nSpecies+iDim)
        / (Primitive(iPoint,RHO_INDEX)*Primitive(iPoint,RHO_INDEX));
  }
}

bool CNEMOEulerVariable::SetPrimVar(unsigned long iPoint, CFluidModel *FluidModel) {

  fluidmodel = static_cast<CNEMOGas*>(FluidModel);

  su2double candidateState[MAXNVAR];
  for (auto iVar = 0u; iVar < nVar; ++iVar)
    candidateState[iVar] = Solution(iPoint,iVar);

  const su2double TSeed =
      Primitive(iPoint,T_INDEX);
  const su2double TveSeed =
      Primitive(iPoint,TVE_INDEX);

  const bool candidateNonPhys =
      Cons2PrimVar(
          Solution[iPoint],
          Primitive[iPoint],
          dPdU[iPoint],
          dTdU[iPoint],
          dTvedU[iPoint],
          eves[iPoint],
          Cvves[iPoint]);

  bool storedStateNonPhys = candidateNonPhys;

  /*
   * Use the same thermochemical accepted-state recovery policy as the
   * Navier--Stokes variable path instead of falling back to Solution_Old,
   * which is an integration buffer and is not an admissibility record.
   */
  if (candidateNonPhys) {

    bool recovered = false;
    su2double alpha = 0.5;

    constexpr unsigned short maxBacktrack = 16;

    for (unsigned short iTry = 0;
         iTry < maxBacktrack;
         ++iTry) {

      for (auto iVar = 0u; iVar < nVar; ++iVar) {
        Solution(iPoint,iVar) =
            Solution_Accepted(iPoint,iVar)
            + alpha
            * (candidateState[iVar]
               - Solution_Accepted(iPoint,iVar));
      }

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

      for (auto iVar = 0u; iVar < nVar; ++iVar)
        Solution(iPoint,iVar) =
            Solution_Accepted(iPoint,iVar);

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

      if (acceptedNonPhys) {
        std::cerr
            << "[NEMO_EULER_ACCEPTED_STATE_FAILURE]"
            << " point=" << iPoint
            << " rhoE_accepted="
            << Solution_Accepted(iPoint,nSpecies+nDim)
            << " rhoEve_accepted="
            << Solution_Accepted(iPoint,nSpecies+nDim+1)
            << " T=" << Primitive(iPoint,T_INDEX)
            << " Tve=" << Primitive(iPoint,TVE_INDEX)
            << std::endl;

        SU2_MPI::Error(
            "NEMO Euler last-accepted thermochemical state failed "
            "conservative-to-primitive recovery.",
            CURRENT_FUNCTION);
      }

      storedStateNonPhys = false;
    }
  }

  if (!storedStateNonPhys) {
    for (auto iVar = 0u; iVar < nVar; ++iVar)
      Solution_Accepted(iPoint,iVar) = Solution(iPoint,iVar);
  }

  /*--- Set additional point quantities ---*/
  Gamma(iPoint) = fluidmodel->ComputeGamma();

  SetVelocity2(iPoint);

  return candidateNonPhys;
}


su2double CNEMOEulerVariable::ComputeAdmissibleImplicitStep(
    unsigned long iPoint,
    const su2double *deltaU,
    su2double initial_alpha,
    CFluidModel *FluidModel,
    unsigned short max_backtracks) {

  if (initial_alpha <= 0.0) return 0.0;

  /*
   * Trial buffers are completely local.  In particular, Cons2PrimVar()
   * is allowed to floor a trace negative species in Utrial without
   * changing the live conservative solution stored in Solution.
   */
  std::vector<su2double> Utrial(nVar, 0.0);
  std::vector<su2double> Vtrial(nSpecies + nDim + 10, 0.0);

  std::vector<su2double> dPdU(nVar, 0.0);
  std::vector<su2double> dTdU(nVar, 0.0);
  std::vector<su2double> dTvedU(nVar, 0.0);

  std::vector<su2double> eves(nSpecies, 0.0);
  std::vector<su2double> Cvves(nSpecies, 0.0);

  const su2double TSeed = Primitive(iPoint, T_INDEX);
  const su2double TveSeed = Primitive(iPoint, TVE_INDEX);

  /*
   * Keep an exact copy of the currently accepted thermochemical state.
   * Mutation++ ComputeTemperatures() changes the internal mixture state
   * even when the energy inversion is later rejected, so every trial
   * must begin from this same accepted state.
   */
  std::vector<su2double> live_rhos(nSpecies, 0.0);
  for (unsigned short iSpecies = 0; iSpecies < nSpecies; ++iSpecies)
    live_rhos[iSpecies] = Solution(iPoint, iSpecies);

  auto restoreFluidState = [&]() {
    fluidmodel->SetTDStateRhosTTv(live_rhos, TSeed, TveSeed);
  };

  restoreFluidState();

  su2double alpha = initial_alpha;

  /*
   * Attempt initial_alpha first, followed by max_backtracks halvings.
   * Thus max_backtracks = 0 still tests the original step once.
   */
  for (unsigned short attempt = 0;
       attempt <= max_backtracks;
       ++attempt) {

    for (unsigned short iVar = 0; iVar < nVar; ++iVar) {
      Utrial[iVar] =
          Solution(iPoint, iVar) +
          alpha * deltaU[iVar];
    }

    /*
     * Every attempt must start from the same valid temperature seeds.
     * A failed Mutation++ inversion must not poison the next trial.
     */
    std::fill(Vtrial.begin(), Vtrial.end(), 0.0);
    Vtrial[T_INDEX] = TSeed;
    Vtrial[TVE_INDEX] = TveSeed;

    /*
     * ComputeTemperatures() mutates Mutation++'s internal mixture state.
     * Start every independent trial from the exact accepted state.
     */
    restoreFluidState();

    const bool nonphysical =
        Cons2PrimVar(
            Utrial.data(),
            Vtrial.data(),
            dPdU.data(),
            dTdU.data(),
            dTvedU.data(),
            eves.data(),
            Cvves.data());

    /*
     * Whether this trial succeeds or fails, do not leak its Mutation++
     * state into the next trial or back to the caller.
     */
    restoreFluidState();

    if (!nonphysical &&
        std::isfinite(Vtrial[T_INDEX]) &&
        std::isfinite(Vtrial[TVE_INDEX]) &&
        Vtrial[T_INDEX] > 0.0 &&
        Vtrial[TVE_INDEX] > 0.0) {
      return alpha;
    }

    alpha *= 0.5;
  }

  return 0.0;
}


bool CNEMOEulerVariable::Cons2PrimVar(su2double *U, su2double *V,
                                      su2double *val_dPdU, su2double *val_dTdU,
                                      su2double *val_dTvedU, su2double *val_eves,
                                      su2double *val_Cvves) {

  unsigned short iDim, iSpecies;
  vector<su2double> rhos;

  rhos.resize(nSpecies,0.0);

  /*--- Conserved & primitive vector layout ---*/
  // U:  [rho1, ..., rhoNs, rhou, rhov, rhow, rhoe, rhoeve]^T
  // V: [rho1, ..., rhoNs, T, Tve, u, v, w, P, rho, h, a, rhoCvtr, rhoCvve]^T

  /*--- Set booleans ---*/
  bool nonPhys = false;

  /*--- Set temperature clipping values ---*/
  const su2double Tmin   = fluidmodel->GetMinimumTemperature();
  const su2double Tmax   = fluidmodel->GetMaximumTemperature();
  const su2double Tvemin = fluidmodel->GetMinimumVETemperature();
  const su2double Tvemax = fluidmodel->GetMaximumVETemperature();

  /*--- Rename variables for convenience ---*/
  su2double rhoE   = U[nSpecies+nDim];     // Density * energy [J/m3]
  su2double rhoEve = U[nSpecies+nDim+1];   // Density * energy_ve [J/m3]

  /*--- Assign species & mixture density.
   *
   * Preserve the original NEMO treatment of an individual species
   * undershoot: floor only that species instead of rejecting the
   * complete conservative state.  This is important for trace charged
   * species in AIR-11.
   *---*/
  V[RHO_INDEX] = 0.0;

  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {

    if (U[iSpecies] < 0.0) {
      U[iSpecies] = 1E-20;
      V[RHOS_INDEX+iSpecies] = 1E-20;
      rhos[iSpecies] = 1E-20;
    } else {
      V[RHOS_INDEX+iSpecies] = U[iSpecies];
      rhos[iSpecies] = U[iSpecies];
    }

    V[RHO_INDEX] += U[iSpecies];
  }

  // Rename for convenience
  su2double rho = V[RHO_INDEX];

  /*--- Assign velocity^2 ---*/
  su2double sqvel = 0.0;
  for (iDim = 0; iDim < nDim; iDim++) {
    V[VEL_INDEX+iDim] = U[nSpecies+iDim]/V[RHO_INDEX];
    sqvel            += V[VEL_INDEX+iDim]*V[VEL_INDEX+iDim];
  }

  /*--- Assign temperatures ---*/
  const su2double Tve_old = V[TVE_INDEX];
  const auto& T = fluidmodel->ComputeTemperatures(rhos, rhoE, rhoEve, 0.5*rho*sqvel, Tve_old);

  /*--- Temperatures ---*/
  V[T_INDEX]   = T[0];
  V[TVE_INDEX] = T[1];

  // Determine if the temperature lies within the acceptable range
  if (!std::isfinite(V[T_INDEX]) ||
      V[T_INDEX] <= Tmin ||
      V[T_INDEX] >= Tmax) {
    nonPhys = true;
    return nonPhys;
  }

  if (!monoatomic){
    if (!std::isfinite(V[TVE_INDEX]) ||
        V[TVE_INDEX] <= Tvemin ||
        V[TVE_INDEX] >= Tvemax) {
      nonPhys = true;
      return nonPhys;
    }
  }
  else {V[TVE_INDEX] = Tve_Freestream;}

  // Determine other properties of the mixture at the current state
  fluidmodel->SetTDStateRhosTTv(rhos, V[T_INDEX], V[TVE_INDEX]);

  const auto& cvves = fluidmodel->ComputeSpeciesCvVibEle(V[TVE_INDEX]);
  vector<su2double> eves  = fluidmodel->ComputeSpeciesEve(V[TVE_INDEX]);

  for (iSpecies = 0; iSpecies < nSpecies; iSpecies++) {
    val_eves[iSpecies]  = eves[iSpecies];
    val_Cvves[iSpecies] = cvves[iSpecies];
  }

  V[RHOCVTR_INDEX] = fluidmodel->ComputerhoCvtr();
  V[RHOCVVE_INDEX] = fluidmodel->ComputerhoCvve();

  /*--- Pressure ---*/
  V[P_INDEX] = fluidmodel->ComputePressure();

  if (V[P_INDEX] < 0.0) {
    V[P_INDEX] = 1E-20;
    nonPhys = true;
  }

  /*--- Partial derivatives of pressure and temperature ---*/
  if(implicit){
    fluidmodel->ComputedPdU  (V, eves, val_dPdU  );
    fluidmodel->ComputedTdU  (V, val_dTdU );
    fluidmodel->ComputedTvedU(V, eves, val_dTvedU);
  }

  /*--- Sound speed ---*/
  V[A_INDEX] = fluidmodel->ComputeSoundSpeed();

  /*--- Enthalpy ---*/
  V[H_INDEX] = (U[nSpecies+nDim] + V[P_INDEX])/V[RHO_INDEX];

  return nonPhys;
}
