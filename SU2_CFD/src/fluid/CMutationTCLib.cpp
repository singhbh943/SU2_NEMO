/*!
 * \file CMutationTCLib.cpp
 * \brief Source of the Mutation++ 2T nonequilibrium gas model.
 * \author C. Garbacz
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

#if defined(HAVE_MPP) && !defined(CODI_REVERSE_TYPE) && !defined(CODI_FORWARD_TYPE)

#include "../../include/fluid/CMutationTCLib.hpp"
#include <cmath>
#include <limits>

CMutationTCLib::CMutationTCLib(const CConfig* config, unsigned short val_nDim): CNEMOGas(config, val_nDim){

  Mutation::MixtureOptions opt(gas_model);
  string transport_model;

  /* Allocating memory*/
  Cv_ks.resize(nEnergyEq*nSpecies,0.0);
  es.resize(nEnergyEq*nSpecies,0.0);
  omega_vec.resize(1,0.0);
  CatRecombTable.resize(nSpecies,2) = 0;

  /*--- Set up inputs to define type of mixture in the Mutation++ library ---*/

  /*--- Define transport model ---*/
  if(Kind_TransCoeffModel == TRANSCOEFFMODEL::WILKE)
    transport_model = "Wilke";
  else if (Kind_TransCoeffModel == TRANSCOEFFMODEL::GUPTAYOS)
    transport_model = "Gupta-Yos";
  else if (Kind_TransCoeffModel == TRANSCOEFFMODEL::CHAPMANN_ENSKOG)
    transport_model = "Chapmann-Enskog_LDLT";

  opt.setStateModel("ChemNonEqTTv");
  if (frozen) opt.setMechanism("none");
  opt.setViscosityAlgorithm(transport_model);
  opt.setThermalConductivityAlgorithm(transport_model);

  /* Initialize mixture object */
  mix.reset(new Mutation::Mixture(opt));

  /*
   * SU2 sizes all NEMO species arrays from GAS_COMPOSITION, whereas
   * Mutation++ obtains its species count from the selected mixture.
   * A mismatch would otherwise lead to out-of-bounds access below
   * (for example while building the catalytic recombination table).
   */
  if (static_cast<unsigned short>(mix->nSpecies()) != nSpecies) {
    SU2_MPI::Error(
        "Mutation++ mixture '" + gas_model + "' contains " +
        std::to_string(mix->nSpecies()) +
        " species, but SU2 GAS_COMPOSITION defines " +
        std::to_string(nSpecies) + ".",
        CURRENT_FUNCTION);
  }

  // x1000 to have Molar Mass in kg/kmol
  for(iSpecies = 0; iSpecies < nSpecies; iSpecies++)
    MolarMass[iSpecies] = 1000* mix->speciesMw(iSpecies);

  if (mix->hasElectrons()) { nHeavy = nSpecies-1; nEl = 1; }
  else { nHeavy = nSpecies; nEl = 0; }

  /*--- Set up catalytic recombination table. -----------------------------*/
  /*
   * Catalytic recombination map.
   *
   * Column 0:
   *   +1 : species produced at the wall
   *   -1 : species consumed at the wall
   *    0 : species unaffected by the neutral catalytic model
   *
   * Column 1:
   *   Index of the incident atomic species controlling the wall flux.
   *
   * Supported heterogeneous neutral reactions:
   *
   *       N + N -> N2
   *       O + O -> O2
   *
   * Species are identified by their Mutation++ names instead of fixed
   * array positions.  This makes the catalytic-wall model compatible
   * with different mixture orderings, including AIR-5, AIR-7 and
   * AIR-11.
   *
   * Charged species and electrons are left catalytically inactive here.
   * Their wall interaction requires a separate plasma-wall model.
   */

  /*--- Default: every species has zero catalytic source. ---*/
  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {
    CatRecombTable(iSpecies, 0) = 0;
    CatRecombTable(iSpecies, 1) = iSpecies;
  }

  /*--- Obtain actual Mutation++ species indices. ---*/
  const int iN  = mix->speciesIndex("N");
  const int iO  = mix->speciesIndex("O");
  const int iN2 = mix->speciesIndex("N2");
  const int iO2 = mix->speciesIndex("O2");

  bool nitrogen_recombination = false;
  bool oxygen_recombination   = false;

  /*--- Nitrogen heterogeneous recombination: N + N -> N2. ---*/
  if ((iN >= 0) && (iN2 >= 0)) {

    /* Atomic nitrogen is removed from the gas. */
    CatRecombTable(iN, 0) = -1;
    CatRecombTable(iN, 1) = iN;

    /* Molecular nitrogen receives the corresponding mass flux. */
    CatRecombTable(iN2, 0) = 1;
    CatRecombTable(iN2, 1) = iN;

    nitrogen_recombination = true;
  }

  /*--- Oxygen heterogeneous recombination: O + O -> O2. ---*/
  if ((iO >= 0) && (iO2 >= 0)) {

    /* Atomic oxygen is removed from the gas. */
    CatRecombTable(iO, 0) = -1;
    CatRecombTable(iO, 1) = iO;

    /* Molecular oxygen receives the corresponding mass flux. */
    CatRecombTable(iO2, 0) = 1;
    CatRecombTable(iO2, 1) = iO;

    oxygen_recombination = true;
  }

  /*
   * A catalytic wall is meaningful only if at least one supported
   * recombination pair is present in the selected Mutation++ mixture.
   */
  if (config->GetCatalytic() &&
      !nitrogen_recombination &&
      !oxygen_recombination) {

    SU2_MPI::Error(
        "Catalytic wall requested but the Mutation++ mixture does not "
        "contain a supported N/N2 or O/O2 recombination pair.",
        CURRENT_FUNCTION);
  }

}

CMutationTCLib::~CMutationTCLib(){}

void CMutationTCLib::SetTDStateRhosTTv(vector<su2double>& val_rhos, su2double val_temperature, su2double val_temperature_ve){

  temperatures[0] = val_temperature;
  temperatures[1] = val_temperature_ve;

  T   = temperatures[0];
  Tve = temperatures[1];

  rhos = val_rhos;

  Density = 0.0;
  for (iSpecies = 0; iSpecies < nSpecies; iSpecies++)
    Density += rhos[iSpecies];

  Pressure = ComputePressure();

  mix->setState(rhos.data(), temperatures.data(), 1);

}

vector<su2double>& CMutationTCLib::GetSpeciesMolarMass(){

   for(iSpecies = 0; iSpecies < nSpecies; iSpecies++) MolarMass[iSpecies] = 1000* mix->speciesMw(iSpecies); // x1000 to have Molar Mass in kg/kmol

   return MolarMass;
}

vector<su2double>& CMutationTCLib::GetSpeciesCvTraRot(){

   mix->getCvsMass(Cv_ks.data());

   for(iSpecies = 0; iSpecies < nSpecies; iSpecies++) Cvtrs[iSpecies] = Cv_ks[iSpecies];

   return Cvtrs;
}


vector<su2double>& CMutationTCLib::ComputeSpeciesCvVibEle(su2double val_T){

   mix->getCvsMass(Cv_ks.data());

   for(iSpecies = 0; iSpecies < nSpecies; iSpecies++) Cvves[iSpecies] = Cv_ks[nSpecies+iSpecies];

   return Cvves;
}

su2double CMutationTCLib::ComputerhoCvve(){

  /*
   * ChemNonEqTTv advances the second conserved energy with the second
   * species-energy row returned by getEnergiesMass().  For ionized
   * mixtures, summing the mode-specific values returned by getCvsMass()
   * is not exactly the derivative of that energy definition (the
   * electron contribution is the important case).  Differentiate the
   * actual Mutation++ V-E energy density locally instead.
   */
  const su2double T0 = T;
  const su2double Tve0 = Tve;
  const su2double abs_Tve = std::abs(Tve0);
  const su2double dTve =
      2.0e-6 * ((abs_Tve > 1.0) ? abs_Tve : su2double(1.0));

  auto eve_density = [&](const su2double probe_Tve) {
    temperatures[0] = T0;
    temperatures[1] = probe_Tve;
    mix->setState(rhos.data(), temperatures.data(), 1);
    mix->getEnergiesMass(es.data());

    su2double value = 0.0;
    for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies)
      value += rhos[iSpecies] * es[nSpecies+iSpecies];

    return value;
  };

  const su2double eve_plus = eve_density(Tve0 + dTve);
  const su2double eve_minus = eve_density(Tve0 - dTve);
  rhoCvve = (eve_plus - eve_minus) / (2.0*dTve);

  /*--- Restore the exact Mutation++ state and base species-energy buffer. ---*/
  temperatures[0] = T0;
  temperatures[1] = Tve0;
  mix->setState(rhos.data(), temperatures.data(), 1);
  mix->getEnergiesMass(es.data());

  if ((!std::isfinite(rhoCvve)) || (rhoCvve <= 0.0))
    SU2_MPI::Error("Invalid Mutation++ V-E heat-capacity derivative.", CURRENT_FUNCTION);

  return rhoCvve;
}

void CMutationTCLib::ComputedTdU(const su2double *V, su2double *val_dTdU){

  const unsigned long VEL_INDEX = nSpecies+2;
  const unsigned long RHOCVTR_INDEX = nSpecies+nDim+6;

  /*
   * The first Mutation++ energy row is the total static internal energy
   * carried by each species, while the second row is the V-E/electron
   * energy.  Their difference is therefore the part controlled by T.
   * Using these two rows avoids reconstructing the energy from formation
   * enthalpy/reference-temperature data and also supplies the missing
   * electron-density derivative.
   */
  mix->getEnergiesMass(es.data());

  const su2double rhoCvtr_local = V[RHOCVTR_INDEX];

  su2double velocity2 = 0.0;
  for (iDim = 0; iDim < nDim; ++iDim)
    velocity2 += V[VEL_INDEX+iDim] * V[VEL_INDEX+iDim];

  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {
    const su2double e_tr =
        es[iSpecies] - es[nSpecies+iSpecies];

    val_dTdU[iSpecies] =
        (0.5*velocity2 - e_tr) / rhoCvtr_local;
  }

  for (iDim = 0; iDim < nDim; ++iDim)
    val_dTdU[nSpecies+iDim] =
        -V[VEL_INDEX+iDim] / rhoCvtr_local;

  val_dTdU[nSpecies+nDim] =
      1.0 / rhoCvtr_local;

  val_dTdU[nSpecies+nDim+1] =
      -1.0 / rhoCvtr_local;
}


void CMutationTCLib::ComputedPdU(
    const su2double *V,
    const vector<su2double>& val_eves,
    su2double *val_dPdU) {

  if (val_dPdU == nullptr)
    SU2_MPI::Error(
        "Array dPdU not allocated!",
        CURRENT_FUNCTION);

  const unsigned short nVarLocal =
      nSpecies + nDim + 2;

  const unsigned long T_INDEX =
      nSpecies;

  const unsigned long TVE_INDEX =
      nSpecies + 1;

  /*
   * NEMO evaluates pressure as
   *
   *   p =
   *     sum_e rho_s (Ru/M_s) Tve
   *     + sum_h rho_s (Ru/M_s) T.
   *
   * The inherited CNEMOGas closed-form derivative predates
   * Mutation++ ChemNonEqTTv's two-mode energy definition.
   *
   * Build dp/dU directly from the pressure chain rule using
   * the already validated Mutation++-consistent dT/dU and
   * dTve/dU derivatives.
   */
  vector<su2double> dTdU_local(
      nVarLocal, 0.0);

  vector<su2double> dTvedU_local(
      nVarLocal, 0.0);

  ComputedTdU(
      V,
      dTdU_local.data());

  ComputedTvedU(
      V,
      val_eves,
      dTvedU_local.data());

  const auto& molar_mass =
      GetSpeciesMolarMass();

  su2double rhoR_electron = 0.0;
  su2double rhoR_heavy = 0.0;

  for (iSpecies = 0;
       iSpecies < nEl;
       ++iSpecies) {

    rhoR_electron +=
        V[iSpecies]
        * Ru
        / molar_mass[iSpecies];
  }

  for (iSpecies = nEl;
       iSpecies < nSpecies;
       ++iSpecies) {

    rhoR_heavy +=
        V[iSpecies]
        * Ru
        / molar_mass[iSpecies];
  }

  for (unsigned short iVar = 0;
       iVar < nVarLocal;
       ++iVar) {

    val_dPdU[iVar] =
        rhoR_heavy
            * dTdU_local[iVar]
        + rhoR_electron
            * dTvedU_local[iVar];
  }

  /*
   * Direct partial-density contribution at fixed
   * T and Tve.
   */
  for (iSpecies = 0;
       iSpecies < nSpecies;
       ++iSpecies) {

    const bool electron =
        (iSpecies < nEl);

    const su2double species_temperature =
        electron
            ? V[TVE_INDEX]
            : V[T_INDEX];

    val_dPdU[iSpecies] +=
        Ru
        / molar_mass[iSpecies]
        * species_temperature;
  }
}


vector<su2double>& CMutationTCLib::ComputeMixtureEnergies(){

  SetTDStateRhosTTv(rhos, T, Tve);

  mix->mixtureEnergies(energies.data());

  return energies;
}

vector<su2double>& CMutationTCLib::ComputeSpeciesEve(su2double val_T, bool vibe_only){

  SetTDStateRhosTTv(rhos, T, val_T);

  mix->getEnergiesMass(es.data());

  for(iSpecies = 0; iSpecies < nSpecies; iSpecies++) eves[iSpecies] = es[nSpecies+iSpecies];

  return eves;
}

vector<su2double>& CMutationTCLib::ComputeNetProductionRates(bool implicit, const su2double *V, const su2double* eve,
                                               const su2double* cvve, const su2double* dTdU, const su2double* dTvedU,
                                               su2double **val_jacobian){

  /*--- Production rates at the current Mutation++ state. ---*/
  mix->netProductionRates(ws.data());

  if (implicit) {

    const unsigned short nVar = nSpecies + nDim + 2;

    const unsigned long T_INDEX   = nSpecies;
    const unsigned long TVE_INDEX = nSpecies + 1;

    /*
     * Mutation++ analytic composition Jacobian:
     *
     *   J_rho(i,j) = d omega_i / d rho_j |_T,Tve
     *
     * Row-major storage is documented by Mutation++.
     */
    vector<su2double> jac_rho(nSpecies*nSpecies, 0.0);
    mix->jacobianRho(jac_rho.data());

    /*
     * Species conservative variables are the species partial densities:
     *
     *   U_s = rho_s
     */
    vector<su2double> state_rhos(nSpecies, 0.0);
    for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies)
      state_rhos[iSpecies] = V[iSpecies];

    const su2double T0   = V[T_INDEX];
    const su2double Tve0 = V[TVE_INDEX];

    /*
     * Centered temperature perturbations.
     *
     * 1e-5 is close to the O(eps^(1/3)) scale appropriate for a
     * centered first derivative in double precision while remaining
     * sufficiently local for the thermochemical source.
     */
    const su2double rel_step = 1.0e-5;

    const su2double abs_T   = (T0   >= 0.0) ? T0   : -T0;
    const su2double abs_Tve = (Tve0 >= 0.0) ? Tve0 : -Tve0;

    const su2double dT =
        rel_step * ((abs_T > 1.0) ? abs_T : 1.0);

    const su2double dTve =
        rel_step * ((abs_Tve > 1.0) ? abs_Tve : 1.0);

    vector<su2double> w_T_plus(nSpecies, 0.0);
    vector<su2double> w_T_minus(nSpecies, 0.0);
    vector<su2double> w_Tve_plus(nSpecies, 0.0);
    vector<su2double> w_Tve_minus(nSpecies, 0.0);

    su2double perturbed_temperatures[2];

    /*--- d omega / dT at fixed rho_s and Tve. ---*/
    perturbed_temperatures[0] = T0 + dT;
    perturbed_temperatures[1] = Tve0;

    mix->setState(state_rhos.data(), perturbed_temperatures, 1);
    mix->netProductionRates(w_T_plus.data());

    perturbed_temperatures[0] = T0 - dT;
    perturbed_temperatures[1] = Tve0;

    mix->setState(state_rhos.data(), perturbed_temperatures, 1);
    mix->netProductionRates(w_T_minus.data());

    /*--- d omega / dTve at fixed rho_s and T. ---*/
    perturbed_temperatures[0] = T0;
    perturbed_temperatures[1] = Tve0 + dTve;

    mix->setState(state_rhos.data(), perturbed_temperatures, 1);
    mix->netProductionRates(w_Tve_plus.data());

    perturbed_temperatures[0] = T0;
    perturbed_temperatures[1] = Tve0 - dTve;

    mix->setState(state_rhos.data(), perturbed_temperatures, 1);
    mix->netProductionRates(w_Tve_minus.data());

    /*--- Restore the exact thermochemical state present on entry. ---*/
    perturbed_temperatures[0] = T0;
    perturbed_temperatures[1] = Tve0;

    mix->setState(state_rhos.data(), perturbed_temperatures, 1);

    /*
     * Conservative-variable chemistry Jacobian:
     *
     * d omega_i / dU_j
     *   = J_rho(i,j)
     *   + d omega_i/dT   * dT/dU_j
     *   + d omega_i/dTve * dTve/dU_j.
     */
    for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {

      const su2double dwdT =
          (w_T_plus[iSpecies] - w_T_minus[iSpecies]) /
          (2.0*dT);

      const su2double dwdTve =
          (w_Tve_plus[iSpecies] - w_Tve_minus[iSpecies]) /
          (2.0*dTve);

      for (unsigned short iVar = 0; iVar < nVar; ++iVar) {

        su2double domegadU =
            dwdT   * dTdU[iVar] +
            dwdTve * dTvedU[iVar];

        if (iVar < nSpecies)
          domegadU += jac_rho[iSpecies*nSpecies + iVar];

        val_jacobian[iSpecies][iVar] += domegadU;
      }
    }
  }

  return ws;
}

su2double CMutationTCLib::ComputeEveSourceTerm(){

  mix->energyTransferSource(omega_vec.data());

  omega = omega_vec[0];

  return omega;
}

void CMutationTCLib::GetEveSourceTermJacobian(
    const su2double *V, const su2double *eve, const su2double *cvve,
    const su2double *dTdU, const su2double *dTvedU,
    su2double **val_jacobian) {

  const unsigned short nVar = nSpecies + nDim + 2;
  const unsigned short nEve = nSpecies + nDim + 1;

  const unsigned long T_INDEX   = nSpecies;
  const unsigned long TVE_INDEX = nSpecies + 1;

  /*
   * Mutation++ does not currently provide derivatives of the 2-T energy
   * transfer source.  Different transfer models contribute to this source
   * (not only the chemical omega_s e_ve,s term), so differentiate the
   * complete energyTransferSource() numerically and then apply SU2's
   * conservative-variable temperature chain rule.
   *
   * The eve/cvve arguments are intentionally unused here: they belong to
   * the common CNEMOGas interface and are needed by the native SU2 model,
   * but Mutation++ supplies the complete V-E source directly.
   */
  (void)eve;
  (void)cvve;

  vector<su2double> state_rhos(nSpecies, 0.0);
  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies)
    state_rhos[iSpecies] = V[iSpecies];

  const su2double T0   = V[T_INDEX];
  const su2double Tve0 = V[TVE_INDEX];

  const su2double rel_step = 1.0e-5;
  const su2double rho_floor = 1.0e-12;

  auto abs_value = [](const su2double value) {
    return (value >= 0.0) ? value : -value;
  };

  auto energy_source =
      [&](const vector<su2double>& densities,
          const su2double temperature,
          const su2double temperature_ve) {

    su2double local_temperatures[2] = {temperature, temperature_ve};
    mix->setState(densities.data(), local_temperatures, 1);
    mix->energyTransferSource(omega_vec.data());
    return omega_vec[0];
  };

  /*--- Direct derivatives at fixed temperatures: dQve/drho_s. ---*/
  vector<su2double> dQdrho(nSpecies, 0.0);

  const su2double base_source = energy_source(state_rhos, T0, Tve0);

  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {

    const su2double rho0 = state_rhos[iSpecies];
    const su2double rho_scale =
        (abs_value(rho0) > rho_floor) ? abs_value(rho0) : rho_floor;
    const su2double drho = rel_step * rho_scale;

    state_rhos[iSpecies] = rho0 + drho;
    const su2double source_plus = energy_source(state_rhos, T0, Tve0);

    if (rho0 > drho) {
      state_rhos[iSpecies] = rho0 - drho;
      const su2double source_minus = energy_source(state_rhos, T0, Tve0);
      dQdrho[iSpecies] = (source_plus - source_minus) / (2.0 * drho);
    } else {
      /*--- Keep non-negative densities for zero/trace species. ---*/
      dQdrho[iSpecies] = (source_plus - base_source) / drho;
    }

    state_rhos[iSpecies] = rho0;
  }

  /*--- Temperature derivatives at fixed species densities. ---*/
  const su2double abs_T   = abs_value(T0);
  const su2double abs_Tve = abs_value(Tve0);

  const su2double dT =
      rel_step * ((abs_T > 1.0) ? abs_T : 1.0);
  const su2double dTve =
      rel_step * ((abs_Tve > 1.0) ? abs_Tve : 1.0);

  const su2double source_T_plus =
      energy_source(state_rhos, T0 + dT, Tve0);
  const su2double source_T_minus =
      energy_source(state_rhos, T0 - dT, Tve0);
  const su2double dQdT =
      (source_T_plus - source_T_minus) / (2.0 * dT);

  const su2double source_Tve_plus =
      energy_source(state_rhos, T0, Tve0 + dTve);
  const su2double source_Tve_minus =
      energy_source(state_rhos, T0, Tve0 - dTve);
  const su2double dQdTve =
      (source_Tve_plus - source_Tve_minus) / (2.0 * dTve);

  /*--- Restore the exact thermochemical state present on entry. ---*/
  energy_source(state_rhos, T0, Tve0);

  /*
   * Qve = Qve(rho_1,...,rho_ns,T,Tve), hence
   *
   * dQve/dU_j = dQve/drho_j
   *            + dQve/dT   dT/dU_j
   *            + dQve/dTve dTve/dU_j.
   */
  for (unsigned short iVar = 0; iVar < nVar; ++iVar) {

    su2double dQdU =
        dQdT   * dTdU[iVar] +
        dQdTve * dTvedU[iVar];

    if (iVar < nSpecies)
      dQdU += dQdrho[iVar];

    val_jacobian[nEve][iVar] += dQdU;
  }
}

vector<su2double>& CMutationTCLib::ComputeSpeciesEnthalpy(su2double val_T, su2double val_Tve, su2double *val_eves){

  /*
   * getEnthalpiesMass() evaluates the current Mutation++ state.  Make the
   * temperature arguments of this SU2 interface authoritative instead of
   * silently returning properties from whichever state was evaluated last.
   * The caller is responsible for loading the appropriate species densities.
   */
  SetTDStateRhosTTv(rhos, val_T, val_Tve);
  mix->getEnthalpiesMass(hs.data());

  return hs;
}

vector<su2double>& CMutationTCLib::GetDiffusionCoeff(){

  mix->averageDiffusionCoeffs(DiffusionCoeff.data());

  return DiffusionCoeff;
}

bool CMutationTCLib::ComputeStefanMaxwellDiffusionVelocities(
    const vector<su2double>& val_grad_rhos,
    su2double val_grad_T,
    su2double val_grad_Tve,
    vector<su2double>& val_diffusion_velocity,
    su2double& val_ambipolar_electric_field) {

  /*
   * Only an ionized Mutation++ mixture requires the ambipolar closure.
   * Returning false preserves the historical NEMO diffusion path for
   * neutral Mutation++ mixtures.
   */
  if (!mix->hasElectrons())
    return false;

  if (val_grad_rhos.size() != nSpecies) {
    SU2_MPI::Error(
        "Mutation++ Stefan-Maxwell gradient vector has invalid size.",
        CURRENT_FUNCTION);
  }

  if (rhos.size() != nSpecies || MolarMass.size() != nSpecies) {
    SU2_MPI::Error(
        "Mutation++ Stefan-Maxwell thermochemical state has invalid size.",
        CURRENT_FUNCTION);
  }

  if (!(std::isfinite(T) && T > 0.0 &&
        std::isfinite(Tve) && Tve > 0.0)) {
    SU2_MPI::Error(
        "Mutation++ Stefan-Maxwell transport received invalid temperatures.",
        CURRENT_FUNCTION);
  }

  /*
   * MolarMass is stored by SU2 in kg/kmol, therefore use the universal
   * gas constant in J/(kmol K).
   */
  const su2double Ru_kmol =
      1000.0 * UNIVERSAL_GAS_CONSTANT;

  su2double rho_mix = 0.0;
  su2double molar_concentration = 0.0;

  for (auto iSpecies = 0u; iSpecies < nSpecies; ++iSpecies) {

    if (!(std::isfinite(rhos[iSpecies]) &&
          rhos[iSpecies] >= 0.0 &&
          std::isfinite(MolarMass[iSpecies]) &&
          MolarMass[iSpecies] > 0.0 &&
          std::isfinite(val_grad_rhos[iSpecies]))) {
      SU2_MPI::Error(
          "Invalid Mutation++ state supplied to Stefan-Maxwell transport.",
          CURRENT_FUNCTION);
    }

    rho_mix += rhos[iSpecies];
    molar_concentration +=
        rhos[iSpecies] / MolarMass[iSpecies];
  }

  if (!(std::isfinite(rho_mix) && rho_mix > 0.0 &&
        std::isfinite(molar_concentration) &&
        molar_concentration > 0.0)) {
    SU2_MPI::Error(
        "Degenerate mixture state in Mutation++ Stefan-Maxwell transport.",
        CURRENT_FUNCTION);
  }

  /*
   * Mutation++ ChemNonEqTTv places the free electron at species index 0.
   * This is also the convention used internally by Transport::stefanMaxwell.
   */
  vector<su2double> grad_partial_pressure(nSpecies, 0.0);

  su2double grad_pressure = 0.0;

  for (auto iSpecies = 0u; iSpecies < nSpecies; ++iSpecies) {

    const bool electron = (iSpecies == 0u);

    const su2double Ti =
        electron ? Tve : T;

    const su2double grad_Ti =
        electron ? val_grad_Tve : val_grad_T;

    const su2double ci =
        rhos[iSpecies] / MolarMass[iSpecies];

    const su2double grad_ci =
        val_grad_rhos[iSpecies] / MolarMass[iSpecies];

    grad_partial_pressure[iSpecies] =
        Ru_kmol * (Ti * grad_ci + ci * grad_Ti);

    grad_pressure +=
        grad_partial_pressure[iSpecies];
  }

  /*
   * n*k_B*T_h = c_total*R_u*T_h.
   *
   * Preserve SU2 NEMO's existing no-explicit-Soret transport closure.
   * The pressure/composition and two-temperature partial-pressure
   * contributions are included here, while thermal-diffusion ratios are
   * intentionally not silently activated.
   */
  const su2double denominator =
      molar_concentration * Ru_kmol * T;

  if (!(std::isfinite(denominator) && denominator > 0.0)) {
    SU2_MPI::Error(
        "Invalid Stefan-Maxwell driving-force denominator.",
        CURRENT_FUNCTION);
  }

  vector<su2double> driving_force(nSpecies, 0.0);

  for (auto iSpecies = 0u; iSpecies < nSpecies; ++iSpecies) {

    const su2double Ys =
        rhos[iSpecies] / rho_mix;

    driving_force[iSpecies] =
        (grad_partial_pressure[iSpecies] -
         Ys * grad_pressure) /
        denominator;
  }

  val_diffusion_velocity.assign(nSpecies, 0.0);
  val_ambipolar_electric_field = 0.0;

  /*
   * order = 1:
   * use the production Ramshaw generalized Stefan-Maxwell system without
   * enabling higher-order collision corrections or their diagnostic output.
   *
   * Mutation++ simultaneously solves for the ambipolar electric field and
   * applies its mass-average velocity correction.
   */
  mix->stefanMaxwell(
      T,
      Tve,
      driving_force.data(),
      val_diffusion_velocity.data(),
      val_ambipolar_electric_field,
      1);

  if (!std::isfinite(val_ambipolar_electric_field)) {
    SU2_MPI::Error(
        "Mutation++ returned a non-finite ambipolar electric field.",
        CURRENT_FUNCTION);
  }

  for (auto iSpecies = 0u; iSpecies < nSpecies; ++iSpecies) {
    if (!std::isfinite(val_diffusion_velocity[iSpecies])) {
      SU2_MPI::Error(
          "Mutation++ returned a non-finite Stefan-Maxwell diffusion velocity.",
          CURRENT_FUNCTION);
    }
  }

  return true;
}

su2double CMutationTCLib::GetViscosity(){

  Mu = mix->viscosity();

  return Mu;
}

vector<su2double>& CMutationTCLib::GetThermalConductivities(){

  mix->frozenThermalConductivityVector(ThermalConductivities.data());

  return ThermalConductivities;
}

vector<su2double>& CMutationTCLib::ComputeTemperatures(vector<su2double>& val_rhos, su2double rhoE, su2double rhoEve, su2double rhoEvel, su2double Tve_old){

  rhos = val_rhos;

  energies[0] = rhoE - rhoEvel;
  energies[1] = rhoEve;

  mix->setState(rhos.data(), energies.data(), 0);
  mix->getTemperatures(temperatures.data());

  T   = temperatures[0];
  Tve = temperatures[1];

  /*
   * ChemNonEqTTvStateModel::solveEnergies() only prints a warning when
   * its nonlinear inversion reaches the iteration limit; it does not
   * propagate a convergence flag.  Consequently, in-range T/Tve values
   * can otherwise be accepted by SU2 even when they do not reproduce
   * the requested conservative energies.
   *
   * Recompute the two mixture energies at the returned state and apply
   * the same absolute/relative closure criterion used internally by
   * Mutation++.
   */
  double rho = 0.0;
  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies)
    rho += rhos[iSpecies];

  /*
   * Reproduce ChemNonEqTTvStateModel::solveEnergies() using the same
   * species-energy array and the original rho_i/rho mass fractions.
   * Avoid mixtureEnergies(), which reconstructs Y through X_TO_Y and
   * introduces a different floating-point path.
   */
  mix->getEnergiesMass(es.data());

  double returnedEnergies[2] = {0.0, 0.0};

  for (iSpecies = 0; iSpecies < nSpecies; ++iSpecies) {
    const double yi = rhos[iSpecies] / rho;

    returnedEnergies[0] += es[iSpecies] * yi;
    returnedEnergies[1] += es[nSpecies + iSpecies] * yi;
  }

  const double targetEnergy     = (rhoE - rhoEvel) / rho;
  const double targetEnergyVe   = rhoEve / rho;

  const double closure0 = returnedEnergies[0] - targetEnergy;
  const double closure1 = returnedEnergies[1] - targetEnergyVe;

  const double closureResidual =
      sqrt(closure0*closure0 + closure1*closure1);

  const double targetNorm =
      sqrt(targetEnergy*targetEnergy +
           targetEnergyVe*targetEnergyVe);

  const double atol = 1.0e-12;

  /*
   * This is an admissibility guard, not Mutation++'s nonlinear
   * convergence criterion.  Allow small post-inversion roundoff
   * while still rejecting genuinely inconsistent energy states.
   */
  const double rtol = 1.0e-10;

  const double closureTolerance = rtol*targetNorm + atol;

  if ((!std::isfinite(closureResidual)) ||
      (closureResidual > closureTolerance)) {

    std::cerr
        << "[MPP_CLOSURE_REJECT]"
        << " rho=" << rho
        << " rawT=" << T
        << " rawTve=" << Tve
        << " targetE=" << targetEnergy
        << " returnedE=" << returnedEnergies[0]
        << " closure0=" << closure0
        << " targetEve=" << targetEnergyVe
        << " returnedEve=" << returnedEnergies[1]
        << " closure1=" << closure1
        << " closureResidual=" << closureResidual
        << " targetNorm=" << targetNorm
        << " closureTolerance=" << closureTolerance
        << std::endl;

    const su2double invalidTemperature =
        std::numeric_limits<su2double>::quiet_NaN();

    temperatures[0] = invalidTemperature;
    temperatures[1] = invalidTemperature;

    T   = invalidTemperature;
    Tve = invalidTemperature;
  }

  return temperatures;
}

vector<su2double>& CMutationTCLib::GetRefTemperature() {

  Tref = mix->standardStateT();

  for (iSpecies = 0; iSpecies < nSpecies; iSpecies++) Ref_Temperature[iSpecies] = Tref;

  return Ref_Temperature;
}

vector<su2double>& CMutationTCLib::GetSpeciesFormationEnthalpy() {

   vector<su2double> hf_RT; hf_RT.resize(nSpecies,0.0);

   Tref = mix->standardStateT();

   mix->speciesHOverRT(Tref, Tref, Tref, Tref, Tref, NULL, NULL, NULL, NULL, NULL, hf_RT.data());

   for (iSpecies = 0; iSpecies < nSpecies; iSpecies++) Enthalpy_Formation[iSpecies] = hf_RT[iSpecies]*(RuSI*Tref*1000.0)/MolarMass[iSpecies];

   return Enthalpy_Formation;
}
#endif
