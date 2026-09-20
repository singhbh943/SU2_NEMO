/*!
 * \file CFluidModel_tests.cpp
 * \brief Unit tests for the fluid model classes.
 * \author E.Bunschoten
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

#include "catch.hpp"
#include <sstream>
#include "../../../SU2_CFD/include/fluid/CFluidModel.hpp"
#include "../../../SU2_CFD/include/fluid/CIdealGas.hpp"
#include "../../../SU2_CFD/include/fluid/CDataDrivenFluid.hpp"

void FluidModelChecks(CFluidModel* fluid_model, const su2double val_p, const su2double val_T) {
  /*--- Check consistency of reverse look-up ---*/
  {
    fluid_model->SetTDState_PT(val_p, val_T);

    const su2double val_rho_fluidmodel = fluid_model->GetDensity();
    const su2double val_e_fluidmodel = fluid_model->GetStaticEnergy();

    fluid_model->SetTDState_rhoe(val_rho_fluidmodel, val_e_fluidmodel);
    CHECK(Approx(fluid_model->GetPressure()) == val_p);
    CHECK(Approx(fluid_model->GetTemperature()) == val_T);
  }
  /*--- Check internal consistency between primary and derived fluid properties ---*/
  fluid_model->SetTDState_PT(val_p, val_T);
  const su2double val_rho = fluid_model->GetDensity();
  const su2double val_e = fluid_model->GetStaticEnergy();

  const su2double dTdrho_e = fluid_model->GetdTdrho_e();
  const su2double dPdrho_e = fluid_model->GetdPdrho_e();
  const su2double dTde_rho = fluid_model->GetdTde_rho();
  const su2double dPde_rho = fluid_model->GetdPde_rho();

  su2double delta_rho = 1e-2, delta_e = 100.0;
  {
    fluid_model->SetTDState_rhoe(val_rho + delta_rho, val_e);
    const su2double T_plus = fluid_model->GetTemperature();
    const su2double p_plus = fluid_model->GetPressure();

    fluid_model->SetTDState_rhoe(val_rho - delta_rho, val_e);
    const su2double T_minus = fluid_model->GetTemperature();
    const su2double p_minus = fluid_model->GetPressure();
    const su2double dTdrho_e_FD = (T_plus - T_minus) / (2 * delta_rho);
    const su2double dPdrho_e_FD = (p_plus - p_minus) / (2 * delta_rho);

    CHECK(dTdrho_e == Approx(dTdrho_e_FD));
    CHECK(dPdrho_e == Approx(dPdrho_e_FD));
  }
  {
    fluid_model->SetTDState_rhoe(val_rho, val_e + delta_e);
    const su2double T_plus = fluid_model->GetTemperature();
    const su2double p_plus = fluid_model->GetPressure();

    fluid_model->SetTDState_rhoe(val_rho, val_e - delta_e);
    const su2double T_minus = fluid_model->GetTemperature();
    const su2double p_minus = fluid_model->GetPressure();
    const su2double dTde_rho_FD = (T_plus - T_minus) / (2 * delta_e);
    const su2double dPde_rho_FD = (p_plus - p_minus) / (2 * delta_e);

    CHECK(dTde_rho == Approx(dTde_rho_FD));
    CHECK(dPde_rho == Approx(dPde_rho_FD));
  }
}

TEST_CASE("Test case for ideal gas fluid model") {
  CIdealGas* fluid_model = new CIdealGas(1.4, 287.0);

  FluidModelChecks(fluid_model, 101325, 300.0);
  FluidModelChecks(fluid_model, 1e6, 600.0);

  delete fluid_model;
}

TEST_CASE("Test case for data-driven fluid model") {
  std::stringstream config_options;

  config_options << "SOLVER=RANS" << std::endl;
  config_options << "KIND_TURB_MODEL=SA" << std::endl;
  config_options << "SA_OPTIONS= NONE" << std::endl;
  config_options << "REYNOLDS_NUMBER=1e6" << std::endl;
  config_options << "FLUID_MODEL=DATADRIVEN_FLUID" << std::endl;
  config_options << "USE_PINN=YES" << std::endl;
  config_options << "INTERPOLATION_METHOD=MLP" << std::endl;
  config_options << "FILENAMES_INTERPOLATOR=(src/SU2/UnitTests/SU2_CFD/fluid/MLP_PINN.mlp)" << std::endl;
  config_options << "CONV_NUM_METHOD_FLOW=JST" << std::endl;

  /*--- Setup ---*/

  CConfig* config = new CConfig(config_options, SU2_COMPONENT::SU2_CFD, false);

  /*--- Define fluid model ---*/
  CDataDrivenFluid* fluid_model = new CDataDrivenFluid(config, false);

  /*--- Check fluid model consistency for several combinations of pressure-temperature. ---*/
  FluidModelChecks(fluid_model, 1.83e6, 523.0);
  FluidModelChecks(fluid_model, 2e5, 520.0);

  delete config;
  delete fluid_model;
}


/* MUTATIONPP_IMPLICIT_CHEM_JAC_TEST_BEGIN */
#if defined(HAVE_MPP) && !defined(CODI_REVERSE_TYPE) && !defined(CODI_FORWARD_TYPE)

#include "../../../SU2_CFD/include/fluid/CMutationTCLib.hpp"
#include "../../../SU2_CFD/include/variables/CNEMONSVariable.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <string>
#include <vector>

namespace {

std::unique_ptr<CConfig> MakeMutationConfig(
    const std::string& gas_model,
    const bool ionization,
    const std::vector<su2double>& rhos) {

  std::stringstream config_options;

  config_options << "SOLVER=NEMO_NAVIER_STOKES" << std::endl;
  config_options << "FLUID_MODEL=MUTATIONPP" << std::endl;
  config_options << "GAS_MODEL=" << gas_model << std::endl;
  config_options << "IONIZATION=" << (ionization ? "YES" : "NO") << std::endl;
  config_options << "TRANSPORT_COEFF_MODEL=WILKE" << std::endl;

  /*
   * SU2 derives nSpecies from the number of GAS_COMPOSITION entries.
   * Keep the unit-test configuration consistent with the Mutation++
   * mixture and with the density vector used by the test.
   */
  su2double rho_sum = 0.0;
  for (const auto rho_i : rhos)
    rho_sum += rho_i;

  config_options << "GAS_COMPOSITION=(";
  for (size_t i = 0; i < rhos.size(); ++i) {
    if (i != 0)
      config_options << ",";
    config_options << rhos[i] / rho_sum;
  }
  config_options << ")" << std::endl;

  return std::unique_ptr<CConfig>(
      new CConfig(config_options, SU2_COMPONENT::SU2_CFD, false));
}

std::vector<su2double> EvaluateMutationChemistry(
    CMutationTCLib& fluid_model,
    std::vector<su2double> rhos,
    const su2double T,
    const su2double Tve) {

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);

  const auto& omega_ref =
      fluid_model.ComputeNetProductionRates(
          false, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr);

  return std::vector<su2double>(omega_ref.begin(), omega_ref.end());
}

su2double EvaluateMutationEveSource(
    CMutationTCLib& fluid_model,
    std::vector<su2double> rhos,
    const su2double T,
    const su2double Tve) {

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  return fluid_model.ComputeEveSourceTerm();
}

void CheckMutationChemistryJacobian(
    const std::string& gas_model,
    const bool ionization,
    std::vector<su2double> rhos,
    const std::vector<unsigned short>& density_columns) {

  auto config = MakeMutationConfig(gas_model, ionization, rhos);

  constexpr unsigned short nDim = 2;
  CMutationTCLib fluid_model(config.get(), nDim);

  const auto& molar_mass = fluid_model.GetSpeciesMolarMass();
  REQUIRE(molar_mass.size() == rhos.size());

  const unsigned short nSpecies =
      static_cast<unsigned short>(rhos.size());
  const unsigned short nVar = nSpecies + nDim + 2;
  const unsigned short nE   = nSpecies + nDim;
  const unsigned short nEve = nSpecies + nDim + 1;

  const su2double T   = 12000.0;
  const su2double Tve = 9000.0;

  std::vector<su2double> V(nSpecies + 2, 0.0);
  for (unsigned short i = 0; i < nSpecies; ++i)
    V[i] = rhos[i];
  V[nSpecies]     = T;
  V[nSpecies + 1] = Tve;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);

  const auto& eve_ref = fluid_model.ComputeSpeciesEve(Tve);
  std::vector<su2double> eve(eve_ref.begin(), eve_ref.end());

  const auto& cvve_ref = fluid_model.ComputeSpeciesCvVibEle(Tve);
  std::vector<su2double> cvve(cvve_ref.begin(), cvve_ref.end());

  /*
   * Synthetic conservative-variable temperature derivatives isolate the
   * direct density, T, and Tve derivatives independently.
   */
  std::vector<su2double> dTdU(nVar, 0.0);
  std::vector<su2double> dTvedU(nVar, 0.0);
  dTdU[nE]       = 1.0;
  dTvedU[nEve]   = 1.0;

  std::vector<std::vector<su2double>>
      jac(nVar, std::vector<su2double>(nVar, 0.0));
  std::vector<su2double*> jac_ptr(nVar, nullptr);
  for (unsigned short i = 0; i < nVar; ++i)
    jac_ptr[i] = jac[i].data();

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  fluid_model.ComputeNetProductionRates(
      true,
      V.data(),
      eve.data(),
      cvve.data(),
      dTdU.data(),
      dTvedU.data(),
      jac_ptr.data());

  auto check_species_column =
      [&](const unsigned short column,
          const std::vector<su2double>& plus,
          const std::vector<su2double>& minus,
          const su2double delta) {

    su2double column_scale = 1.0;
    std::vector<su2double> fd(nSpecies, 0.0);

    for (unsigned short i = 0; i < nSpecies; ++i) {
      fd[i] = (plus[i] - minus[i]) / (2.0 * delta);
      REQUIRE(std::isfinite(fd[i]));
      REQUIRE(std::isfinite(jac[i][column]));
      column_scale = std::max(column_scale, std::abs(fd[i]));
      column_scale = std::max(column_scale, std::abs(jac[i][column]));
    }

    for (unsigned short i = 0; i < nSpecies; ++i) {
      const su2double error =
          std::abs(jac[i][column] - fd[i]) / column_scale;

      CAPTURE(gas_model, column, i,
              jac[i][column], fd[i], column_scale, error);
      CHECK(error < 5.0e-3);
    }
  };

  for (const auto column : density_columns) {
    REQUIRE(column < nSpecies);
    REQUIRE(rhos[column] > 0.0);

    const su2double delta = 1.0e-5 * rhos[column];
    REQUIRE(rhos[column] > delta);

    auto rho_plus  = rhos;
    auto rho_minus = rhos;
    rho_plus[column]  += delta;
    rho_minus[column] -= delta;

    const auto plus =
        EvaluateMutationChemistry(fluid_model, rho_plus, T, Tve);
    const auto minus =
        EvaluateMutationChemistry(fluid_model, rho_minus, T, Tve);

    check_species_column(column, plus, minus, delta);
  }

  {
    const su2double deltaT = 1.0e-5 * T;
    const auto plus =
        EvaluateMutationChemistry(fluid_model, rhos, T + deltaT, Tve);
    const auto minus =
        EvaluateMutationChemistry(fluid_model, rhos, T - deltaT, Tve);
    check_species_column(nE, plus, minus, deltaT);
  }

  {
    const su2double deltaTve = 1.0e-5 * Tve;
    const auto plus =
        EvaluateMutationChemistry(fluid_model, rhos, T, Tve + deltaTve);
    const auto minus =
        EvaluateMutationChemistry(fluid_model, rhos, T, Tve - deltaTve);
    check_species_column(nEve, plus, minus, deltaTve);
  }

  /*
   * ComputeChemistry() has no V-E residual.  The complete Mutation++
   * energy-transfer residual is assembled by ComputeVibRelaxation(), so
   * this Jacobian call must not populate the V-E row and double count it.
   */
  for (unsigned short j = 0; j < nVar; ++j) {
    CAPTURE(gas_model, j, jac[nEve][j]);
    CHECK(jac[nEve][j] == 0.0);
  }
}

void CheckMutationEveSourceJacobian(
    const std::string& gas_model,
    const bool ionization,
    std::vector<su2double> rhos,
    const std::vector<unsigned short>& density_columns) {

  auto config = MakeMutationConfig(gas_model, ionization, rhos);

  constexpr unsigned short nDim = 2;
  CMutationTCLib fluid_model(config.get(), nDim);

  const unsigned short nSpecies =
      static_cast<unsigned short>(rhos.size());
  const unsigned short nVar = nSpecies + nDim + 2;
  const unsigned short nE   = nSpecies + nDim;
  const unsigned short nEve = nSpecies + nDim + 1;

  const su2double T   = 12000.0;
  const su2double Tve = 9000.0;

  std::vector<su2double> V(nSpecies + 2, 0.0);
  for (unsigned short i = 0; i < nSpecies; ++i)
    V[i] = rhos[i];
  V[nSpecies]     = T;
  V[nSpecies + 1] = Tve;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);

  const auto& eve_ref = fluid_model.ComputeSpeciesEve(Tve);
  std::vector<su2double> eve(eve_ref.begin(), eve_ref.end());

  const auto& cvve_ref = fluid_model.ComputeSpeciesCvVibEle(Tve);
  std::vector<su2double> cvve(cvve_ref.begin(), cvve_ref.end());

  std::vector<su2double> dTdU(nVar, 0.0);
  std::vector<su2double> dTvedU(nVar, 0.0);
  dTdU[nE]       = 1.0;
  dTvedU[nEve]   = 1.0;

  std::vector<std::vector<su2double>>
      jac(nVar, std::vector<su2double>(nVar, 0.0));
  std::vector<su2double*> jac_ptr(nVar, nullptr);
  for (unsigned short i = 0; i < nVar; ++i)
    jac_ptr[i] = jac[i].data();

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  fluid_model.GetEveSourceTermJacobian(
      V.data(),
      eve.data(),
      cvve.data(),
      dTdU.data(),
      dTvedU.data(),
      jac_ptr.data());

  auto check_source_column =
      [&](const unsigned short column,
          const su2double plus,
          const su2double minus,
          const su2double delta) {

    const su2double fd = (plus - minus) / (2.0 * delta);
    REQUIRE(std::isfinite(fd));
    REQUIRE(std::isfinite(jac[nEve][column]));

    const su2double scale =
        std::max(su2double(1.0),
                 std::max(std::abs(fd), std::abs(jac[nEve][column])));
    const su2double error =
        std::abs(jac[nEve][column] - fd) / scale;

    CAPTURE(gas_model, column, jac[nEve][column], fd, scale, error);
    CHECK(error < 5.0e-3);
  };

  /*
   * Use a different finite-difference step from the production
   * implementation so this is an independent numerical check.
   */
  for (const auto column : density_columns) {
    REQUIRE(column < nSpecies);
    REQUIRE(rhos[column] > 0.0);

    const su2double delta = 2.0e-6 * rhos[column];
    REQUIRE(rhos[column] > delta);

    auto rho_plus  = rhos;
    auto rho_minus = rhos;
    rho_plus[column]  += delta;
    rho_minus[column] -= delta;

    const su2double plus =
        EvaluateMutationEveSource(fluid_model, rho_plus, T, Tve);
    const su2double minus =
        EvaluateMutationEveSource(fluid_model, rho_minus, T, Tve);

    check_source_column(column, plus, minus, delta);
  }

  {
    const su2double deltaT = 2.0e-6 * T;
    const su2double plus =
        EvaluateMutationEveSource(fluid_model, rhos, T + deltaT, Tve);
    const su2double minus =
        EvaluateMutationEveSource(fluid_model, rhos, T - deltaT, Tve);
    check_source_column(nE, plus, minus, deltaT);
  }

  {
    const su2double deltaTve = 2.0e-6 * Tve;
    const su2double plus =
        EvaluateMutationEveSource(fluid_model, rhos, T, Tve + deltaTve);
    const su2double minus =
        EvaluateMutationEveSource(fluid_model, rhos, T, Tve - deltaTve);
    check_source_column(nEve, plus, minus, deltaTve);
  }
}

}  // namespace


TEST_CASE(
    "Mutation++ AIR-5 implicit chemistry Jacobian matches finite differences",
    "[Mutation++][NEMO][chemistry][air5]") {

  /* Mutation++ AIR-5 ordering: N, O, NO, N2, O2. */
  const std::vector<su2double> rhos = {
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  CheckMutationChemistryJacobian(
      "air_5", false, rhos, {0, 1, 3, 4});

  CheckMutationEveSourceJacobian(
      "air_5", false, rhos, {0, 1, 3, 4});
}




TEST_CASE(
    "NEMO negative species candidate is individually floored",
    "[Mutation++][NEMO][accepted-state][air5]") {

  std::vector<su2double> rhos = {
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_5", false, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 9000.0;
  const su2double Tve = 7000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMONSVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  /* Initialize Primitive and reaffirm the constructor state as accepted. */
  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  const su2double accepted_rho0 = nodes.GetSolution(0, 0);
  REQUIRE(accepted_rho0 > 0.0);

  /*
   * Create a genuinely nonphysical conservative candidate.  The old
   * behavior silently overwrites this value with 1e-20 inside
   * Cons2PrimVar(), so SetPrimVar() never invokes accepted-state
   * backtracking and reports the candidate as physical.
   */
  nodes.SetSolution(0, 0, -0.5 * accepted_rho0);

  const bool reported_nonphysical =
      nodes.SetPrimVar(0, &fluid_model);

  CAPTURE(
      accepted_rho0,
      nodes.GetSolution(0, 0),
      reported_nonphysical);

  CHECK_FALSE( reported_nonphysical );

  /*
   * Recovery must come from the line between the candidate and the last
   * accepted state, not from a hard-coded species-density floor.
   */
  CHECK( nodes.GetSolution(0, 0) == Approx(1.0e-20).margin(1.0e-30) );
  CHECK(nodes.GetSolution(0, 0) < accepted_rho0);
}



TEST_CASE(
    "NEMO Euler negative species candidate is individually floored",
    "[Mutation++][NEMO][accepted-state][euler][air5]") {

  std::vector<su2double> rhos = {
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_5", false, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 9000.0;
  const su2double Tve = 7000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMOEulerVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  const su2double accepted_rho0 = nodes.GetSolution(0, 0);
  REQUIRE(accepted_rho0 > 0.0);

  nodes.SetSolution(0, 0, -0.5 * accepted_rho0);

  const bool reported_nonphysical =
      nodes.SetPrimVar(0, &fluid_model);

  CAPTURE(
      accepted_rho0,
      nodes.GetSolution(0, 0),
      reported_nonphysical);

  CHECK_FALSE( reported_nonphysical );
  CHECK( nodes.GetSolution(0, 0) == Approx(1.0e-20).margin(1.0e-30) );

  /*
   * The Euler path currently jumps all the way to Solution_Old.
   * Desired behavior matches the NS accepted-state line search:
   * retain the largest admissible fraction of the candidate update.
   */
  CHECK(nodes.GetSolution(0, 0) < accepted_rho0);
}


TEST_CASE(
    "Mutation++ species enthalpy honors requested temperatures",
    "[Mutation++][NEMO][enthalpy][air5]") {

  std::vector<su2double> rhos = {
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_5", false, rhos);

  constexpr unsigned short nDim = 2;
  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double target_T   = 9000.0;
  const su2double target_Tve = 7000.0;
  const su2double stale_T    = 3000.0;
  const su2double stale_Tve  = 2500.0;

  /* Build a reference enthalpy vector at the requested state. */
  fluid_model.SetTDStateRhosTTv(rhos, target_T, target_Tve);

  const auto& eve_ref = fluid_model.ComputeSpeciesEve(target_Tve);
  std::vector<su2double> eve(eve_ref.begin(), eve_ref.end());

  fluid_model.SetTDStateRhosTTv(rhos, target_T, target_Tve);

  const auto& h_ref_view =
      fluid_model.ComputeSpeciesEnthalpy(target_T, target_Tve, eve.data());
  const std::vector<su2double> h_ref(h_ref_view.begin(), h_ref_view.end());

  /*
   * Deliberately move Mutation++ to a different state.  The enthalpy
   * routine must still honor the temperatures passed as its arguments,
   * rather than returning properties from this stale state.
   */
  fluid_model.SetTDStateRhosTTv(rhos, stale_T, stale_Tve);

  const auto& h_test_view =
      fluid_model.ComputeSpeciesEnthalpy(target_T, target_Tve, eve.data());
  const std::vector<su2double> h_test(h_test_view.begin(), h_test_view.end());

  REQUIRE(h_test.size() == h_ref.size());

  for (size_t i = 0; i < h_ref.size(); ++i) {
    CAPTURE(i, h_ref[i], h_test[i]);
    CHECK(h_test[i] == Approx(h_ref[i]).epsilon(1.0e-10).margin(1.0e-6));
  }
}



TEST_CASE(
    "Mutation++ AIR-5 partial catalytic wall Jacobian matches finite differences",
    "[Mutation++][NEMO][catalytic-wall][air5]") {

  /* Mutation++ AIR-5 ordering: N, O, NO, N2, O2. */
  std::vector<su2double> rhos = {
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_5", false, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nE = nSpecies + nDim;
  const unsigned long nEve = nSpecies + nDim + 1;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 9000.0;
  const su2double Tve = 7000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMONSVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  std::vector<su2double> U0(nVar, 0.0);
  for (size_t i = 0; i < nVar; ++i)
    U0[i] = nodes.GetSolution(0, i);

  const su2double Tw = 300.0;
  const su2double gam = 0.2;
  const su2double Area = 0.75;
  const su2double Ru = 1000.0 * UNIVERSAL_GAS_CONSTANT;

  const auto& Ms = fluid_model.GetSpeciesMolarMass();
  const auto& RxnTable = fluid_model.GetCatalyticRecombination();

  REQUIRE(Ms.size() == nSpecies);

  /*
   * Evaluate exactly the partial-catalytic residual used by
   * CNEMONSSolver::BC_IsothermalCatalytic_Wall(), but drive its
   * thermodynamic state from the conservative variables through
   * CNEMONSVariable::SetPrimVar().
   */
  auto evaluate_residual =
      [&](const std::vector<su2double>& U) {

    for (size_t i = 0; i < nVar; ++i)
      nodes.SetSolution(0, i, U[i]);

    const bool nonphysical =
        nodes.SetPrimVar(0, &fluid_model);
    REQUIRE_FALSE(nonphysical);

    const auto& V = nodes.GetPrimitive(0);
    const auto& eve_ptr = nodes.GetEve(0);

    const auto& h_view =
        fluid_model.ComputeSpeciesEnthalpy(
            V[nodes.GetTIndex()],
            V[nodes.GetTveIndex()],
            eve_ptr);

    std::vector<su2double> residual(nVar, 0.0);

    const su2double local_rho =
        V[nodes.GetRhoIndex()];

    const su2double factor =
        gam * local_rho *
        std::sqrt(Ru * Tw / (2.0 * PI_NUMBER)) *
        Area;

    for (size_t iSpecies = 0;
         iSpecies < nSpecies;
         ++iSpecies) {

      const int index =
          SU2_TYPE::Int(RxnTable(iSpecies, 1));

      residual[iSpecies] =
          RxnTable(iSpecies, 0) *
          factor *
          V[index] /
          local_rho *
          std::sqrt(1.0 / Ms[index]);
    }

    for (size_t iSpecies = 0;
         iSpecies < nSpecies;
         ++iSpecies) {

      residual[nE] +=
          residual[iSpecies] *
          h_view[iSpecies];

      residual[nEve] +=
          residual[iSpecies] *
          eve_ptr[iSpecies];
    }

    return residual;
  };

  /* Restore the reference state before forming the analytic Jacobian. */
  const auto R0 = evaluate_residual(U0);
  (void)R0;

  const auto& V0 = nodes.GetPrimitive(0);

  std::vector<su2double> species_residual(nSpecies, 0.0);

  const su2double rho0 =
      V0[nodes.GetRhoIndex()];

  const su2double factor0 =
      gam * rho0 *
      std::sqrt(Ru * Tw / (2.0 * PI_NUMBER)) *
      Area;

  for (size_t iSpecies = 0;
       iSpecies < nSpecies;
       ++iSpecies) {

    const int index =
        SU2_TYPE::Int(RxnTable(iSpecies, 1));

    species_residual[iSpecies] =
        RxnTable(iSpecies, 0) *
        factor0 *
        V0[index] /
        rho0 *
        std::sqrt(1.0 / Ms[index]);
  }

  std::vector<std::vector<su2double>>
      jac(nVar, std::vector<su2double>(nVar, 0.0));

  /*
   * Since rho*Y_index = rho_index, the species block is sparse and
   * exact in conservative variables.
   */
  for (size_t iSpecies = 0;
       iSpecies < nSpecies;
       ++iSpecies) {

    const int index =
        SU2_TYPE::Int(RxnTable(iSpecies, 1));

    jac[iSpecies][index] =
        RxnTable(iSpecies, 0) *
        gam *
        std::sqrt(
            Ru * Tw /
            (2.0 * PI_NUMBER * Ms[index])) *
        Area;
  }

  /*
   * Mirror the production wall linearization: differentiate the actual
   * species h_s(T,Tve) and e_ve,s(T,Tve) functions and invert the
   * local two-energy thermodynamic Jacobian.
   */
  const su2double T0 = V0[nodes.GetTIndex()];
  const su2double Tve0 = V0[nodes.GetTveIndex()];
  const su2double rel_step = 2.0e-6;
  const su2double dT =
      rel_step * std::max(std::abs(T0), su2double(1.0));
  const su2double dTve =
      rel_step * std::max(std::abs(Tve0), su2double(1.0));

  std::vector<su2double> h0(nSpecies, 0.0), eve0(nSpecies, 0.0);
  std::vector<su2double> hTp(nSpecies, 0.0), hTm(nSpecies, 0.0);
  std::vector<su2double> hVp(nSpecies, 0.0), hVm(nSpecies, 0.0);
  std::vector<su2double> eTp(nSpecies, 0.0), eTm(nSpecies, 0.0);
  std::vector<su2double> eVp(nSpecies, 0.0), eVm(nSpecies, 0.0);

  auto sample_thermo =
      [&](const su2double Ts,
          const su2double Tves,
          std::vector<su2double>& hout,
          std::vector<su2double>& eout) {

    auto state_rhos = rhos;
    fluid_model.SetTDStateRhosTTv(
        state_rhos, Ts, Tves);

    const auto& eref =
        fluid_model.ComputeSpeciesEve(Tves);

    for (size_t i = 0; i < nSpecies; ++i)
      eout[i] = eref[i];

    const auto& href =
        fluid_model.ComputeSpeciesEnthalpy(
            Ts, Tves, eout.data());

    for (size_t i = 0; i < nSpecies; ++i)
      hout[i] = href[i];
  };

  sample_thermo(T0, Tve0, h0, eve0);
  sample_thermo(T0 + dT, Tve0, hTp, eTp);
  sample_thermo(T0 - dT, Tve0, hTm, eTm);
  sample_thermo(T0, Tve0 + dTve, hVp, eVp);
  sample_thermo(T0, Tve0 - dTve, hVm, eVm);

  std::vector<su2double> dhdT(nSpecies, 0.0);
  std::vector<su2double> dhdTve(nSpecies, 0.0);
  std::vector<su2double> dedT(nSpecies, 0.0);
  std::vector<su2double> dedTve(nSpecies, 0.0);
  std::vector<su2double> eTotal(nSpecies, 0.0);
  std::vector<su2double> deTotaldT(nSpecies, 0.0);
  std::vector<su2double> deTotaldTve(nSpecies, 0.0);

  su2double A = 0.0;
  su2double B = 0.0;
  su2double C = 0.0;
  su2double D = 0.0;

  for (size_t i = 0; i < nSpecies; ++i) {
    dhdT[i] =
        (hTp[i] - hTm[i]) / (2.0 * dT);
    dhdTve[i] =
        (hVp[i] - hVm[i]) / (2.0 * dTve);
    dedT[i] =
        (eTp[i] - eTm[i]) / (2.0 * dT);
    dedTve[i] =
        (eVp[i] - eVm[i]) / (2.0 * dTve);

    eTotal[i] =
        h0[i] - Ru / Ms[i] * T0;

    deTotaldT[i] =
        dhdT[i] - Ru / Ms[i];

    deTotaldTve[i] =
        dhdTve[i];

    A += rhos[i] * deTotaldT[i];
    B += rhos[i] * deTotaldTve[i];
    C += rhos[i] * dedT[i];
    D += rhos[i] * dedTve[i];
  }

  const su2double det = A * D - B * C;
  REQUIRE(std::isfinite(det));
  REQUIRE(std::abs(det) > 0.0);

  std::vector<su2double> wall_dTdU(nVar, 0.0);
  std::vector<su2double> wall_dTvedU(nVar, 0.0);

  for (size_t jVar = 0; jVar < nVar; ++jVar) {

    su2double rhs0 = 0.0;
    su2double rhs1 = 0.0;

    if (jVar < nSpecies) {
      rhs0 = -eTotal[jVar];
      rhs1 = -eve0[jVar];
    } else if (jVar == nE) {
      rhs0 = 1.0;
    } else if (jVar == nEve) {
      rhs1 = 1.0;
    }

    wall_dTdU[jVar] =
        (rhs0 * D - B * rhs1) / det;

    wall_dTvedU[jVar] =
        (A * rhs1 - C * rhs0) / det;
  }

  for (size_t jVar = 0; jVar < nVar; ++jVar) {
    for (size_t iSpecies = 0;
         iSpecies < nSpecies;
         ++iSpecies) {

      jac[nE][jVar] +=
          h0[iSpecies] *
              jac[iSpecies][jVar] +
          species_residual[iSpecies] *
              (dhdT[iSpecies] *
                   wall_dTdU[jVar] +
               dhdTve[iSpecies] *
                   wall_dTvedU[jVar]);

      jac[nEve][jVar] +=
          eve0[iSpecies] *
              jac[iSpecies][jVar] +
          species_residual[iSpecies] *
              (dedT[iSpecies] *
                   wall_dTdU[jVar] +
               dedTve[iSpecies] *
                   wall_dTvedU[jVar]);
    }
  }

  {
    auto state_rhos = rhos;
    fluid_model.SetTDStateRhosTTv(
        state_rhos, T0, Tve0);
  }

  /*
   * Density columns exercise the N/O -> N2/O2 wall coupling.
   * The two energy columns exercise dh_s/dU and de_ve,s/dU.
   */
  const std::vector<size_t> columns = {
      0, 1, 2, 3, 4, nE, nEve
  };

  for (const auto column : columns) {

    su2double delta = 0.0;

    if (column < nSpecies) {
      delta =
          1.0e-5 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0e-12));
      REQUIRE(U0[column] > delta);
    } else {
      delta =
          2.0e-6 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0));
    }

    auto U_plus = U0;
    auto U_minus = U0;
    U_plus[column] += delta;
    U_minus[column] -= delta;

    const auto R_plus =
        evaluate_residual(U_plus);
    const auto R_minus =
        evaluate_residual(U_minus);

    /*
     * Check all species rows and both energy rows. Momentum rows are
     * identically zero for this wall contribution and need no separate
     * finite-difference check here.
     */
    std::vector<size_t> rows;
    for (size_t i = 0; i < nSpecies; ++i)
      rows.push_back(i);
    rows.push_back(nE);
    rows.push_back(nEve);

    for (const auto row : rows) {

      const su2double fd =
          (R_plus[row] - R_minus[row]) /
          (2.0 * delta);

      REQUIRE(std::isfinite(fd));
      REQUIRE(std::isfinite(jac[row][column]));

      const su2double scale =
          std::max(
              su2double(1.0),
              std::max(
                  std::abs(fd),
                  std::abs(jac[row][column])));

      const su2double error =
          std::abs(
              jac[row][column] - fd) /
          scale;

      CAPTURE(
          row,
          column,
          jac[row][column],
          fd,
          scale,
          error);

      CHECK(error < 5.0e-4);
    }
  }

  /* Leave the shared test object at its original physical state. */
  for (size_t i = 0; i < nVar; ++i)
    nodes.SetSolution(0, i, U0[i]);
  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));
}




TEST_CASE(
    "Mutation++ AIR-7 temperature derivatives match conservative finite differences",
    "[Mutation++][NEMO][thermo-derivatives][air7]") {

  /*
   * Use a small but non-zero electron/ion population so the ionized
   * two-temperature coupling is exercised without perturbing through
   * a zero species density.
   */
  std::vector<su2double> rhos = {
      1.0e-8,
      7.0e-4,
      2.0e-4,
      2.0e-5,
      4.0e-5,
      4.0e-5,
      1.0e-8
  };

  auto config = MakeMutationConfig("air_7", true, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 12000.0;
  const su2double Tve = 9000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMONSVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  std::vector<su2double> U0(nVar, 0.0);
  for (size_t i = 0; i < nVar; ++i)
    U0[i] = nodes.GetSolution(0, i);

  std::vector<su2double> analytic_dTdU(nVar, 0.0);
  std::vector<su2double> analytic_dTvedU(nVar, 0.0);

  for (size_t i = 0; i < nVar; ++i) {
    analytic_dTdU[i] = nodes.GetdTdU(0)[i];
    analytic_dTvedU[i] = nodes.GetdTvedU(0)[i];
  }

  auto evaluate_temperatures =
      [&](const std::vector<su2double>& U) {

    for (size_t i = 0; i < nVar; ++i)
      nodes.SetSolution(0, i, U[i]);

    const bool nonphysical =
        nodes.SetPrimVar(0, &fluid_model);
    REQUIRE_FALSE(nonphysical);

    return std::array<su2double, 2>{
        nodes.GetTemperature(0),
        nodes.GetTemperature_ve(0)};
  };

  for (size_t column = 0; column < nVar; ++column) {

    su2double delta = 0.0;

    if (column < nSpecies) {
      delta =
          2.0e-6 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0e-14));
      REQUIRE(U0[column] > delta);
    } else {
      delta =
          2.0e-6 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0));
    }

    auto U_plus = U0;
    auto U_minus = U0;
    U_plus[column] += delta;
    U_minus[column] -= delta;

    const auto plus =
        evaluate_temperatures(U_plus);
    const auto minus =
        evaluate_temperatures(U_minus);

    const su2double fd_dTdU =
        (plus[0] - minus[0]) / (2.0 * delta);
    const su2double fd_dTvedU =
        (plus[1] - minus[1]) / (2.0 * delta);

    const su2double scale_T =
        std::max(
            su2double(1.0),
            std::max(
                std::abs(fd_dTdU),
                std::abs(analytic_dTdU[column])));

    const su2double scale_Tve =
        std::max(
            su2double(1.0),
            std::max(
                std::abs(fd_dTvedU),
                std::abs(analytic_dTvedU[column])));

    const su2double error_T =
        std::abs(
            analytic_dTdU[column] -
            fd_dTdU) /
        scale_T;

    const su2double error_Tve =
        std::abs(
            analytic_dTvedU[column] -
            fd_dTvedU) /
        scale_Tve;

    CAPTURE(
        column,
        analytic_dTdU[column],
        fd_dTdU,
        error_T,
        analytic_dTvedU[column],
        fd_dTvedU,
        error_Tve);

    CHECK(error_T < 5.0e-4);
    CHECK(error_Tve < 5.0e-4);
  }

  for (size_t i = 0; i < nVar; ++i)
    nodes.SetSolution(0, i, U0[i]);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));
}



TEST_CASE(
    "Mutation++ AIR-11 temperature derivatives match conservative finite differences",
    "[Mutation++][NEMO][thermo-derivatives][air11]") {

  /*
   * AIR-11 ordering:
   * e-, N+, O+, NO+, N2+, O2+, N, O, NO, N2, O2.
   *
   * Use a finite, approximately charge-neutral ionized state so every
   * conservative species column can be perturbed with a centered finite
   * difference while exercising electron/heavy-particle coupling.
   */
  std::vector<su2double> rhos = {
      3.61081e-8,
      7.0e-4,
      2.0e-4,
      2.0e-5,
      4.0e-5,
      4.0e-5,
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_11", true, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  const unsigned long P_INDEX = nSpecies + nDim + 2;
  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 12000.0;
  const su2double Tve = 9000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMONSVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  std::vector<su2double> U0(nVar, 0.0);
  for (size_t i = 0; i < nVar; ++i)
    U0[i] = nodes.GetSolution(0, i);

  std::vector<su2double> analytic_dPdU(nVar, 0.0);

  std::vector<su2double> analytic_dTdU(nVar, 0.0);
  std::vector<su2double> analytic_dTvedU(nVar, 0.0);

  for (size_t i = 0; i < nVar; ++i) {
    analytic_dPdU[i] = nodes.GetdPdU(0)[i];
    analytic_dTdU[i] = nodes.GetdTdU(0)[i];
    analytic_dTvedU[i] = nodes.GetdTvedU(0)[i];
  }

  auto evaluate_temperatures =
      [&](const std::vector<su2double>& U) {

    for (size_t i = 0; i < nVar; ++i)
      nodes.SetSolution(0, i, U[i]);

    const bool nonphysical =
        nodes.SetPrimVar(0, &fluid_model);
    REQUIRE_FALSE(nonphysical);

    return std::array<su2double, 3>{
          nodes.GetTemperature(0),
          nodes.GetTemperature_ve(0),
          nodes.GetPrimitive(0)[P_INDEX]};
  };

  for (size_t column = 0; column < nVar; ++column) {

    su2double delta = 0.0;

    if (column < nSpecies) {
      /*
       * Species-density perturbations can produce extremely small
       * temperature changes for weakly V-E-active neutral species
       * (notably O in AIR-11).  Use a 10x larger centered step here to
       * keep the Mutation++ nonlinear energy inversion above its
       * roundoff/closure floor without relaxing the derivative tolerance.
       */
      delta =
          2.0e-5 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0e-14));
      REQUIRE(U0[column] > delta);
    } else {
      delta =
          2.0e-6 *
          std::max(
              std::abs(U0[column]),
              su2double(1.0));
    }

    auto U_plus = U0;
    auto U_minus = U0;
    U_plus[column] += delta;
    U_minus[column] -= delta;

    const auto plus =
        evaluate_temperatures(U_plus);
    const auto minus =
        evaluate_temperatures(U_minus);

    const su2double fd_dTdU =
        (plus[0] - minus[0]) / (2.0 * delta);
    const su2double fd_dTvedU =
        (plus[1] - minus[1]) / (2.0 * delta);
      const su2double fd_dPdU =
          (plus[2] - minus[2]) / (2.0 * delta);

    const su2double scale_P =

        std::max(

            su2double(1.0),

            std::max(

                std::abs(fd_dPdU),

                std::abs(analytic_dPdU[column])));


    const su2double scale_T =
        std::max(
            su2double(1.0),
            std::max(
                std::abs(fd_dTdU),
                std::abs(analytic_dTdU[column])));

    const su2double scale_Tve =
        std::max(
            su2double(1.0),
            std::max(
                std::abs(fd_dTvedU),
                std::abs(analytic_dTvedU[column])));

    const su2double error_P =

        std::abs(

            analytic_dPdU[column] -

            fd_dPdU) /

        scale_P;


    const su2double error_T =
        std::abs(
            analytic_dTdU[column] -
            fd_dTdU) /
        scale_T;

    const su2double error_Tve =
        std::abs(
            analytic_dTvedU[column] -
            fd_dTvedU) /
        scale_Tve;

    CAPTURE(
        column,
          analytic_dPdU[column],
          fd_dPdU,
          error_P,
        analytic_dTdU[column],
        fd_dTdU,
        error_T,
        analytic_dTvedU[column],
        fd_dTvedU,
        error_Tve);

    CHECK(error_P < 5.0e-4);

    CHECK(error_T < 5.0e-4);
    CHECK(error_Tve < 5.0e-4);
  }

  for (size_t i = 0; i < nVar; ++i)
    nodes.SetSolution(0, i, U0[i]);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));
}




TEST_CASE(
    "NEMO AIR-11 implicit thermochemical step limiter backtracks an invalid energy update",
    "[Mutation++][NEMO][implicit][admissibility][air11]") {

  /*
   * Use the same finite ionized AIR-11 state as the thermodynamic
   * derivative regression.  Construct an intentionally excessive
   * negative rhoE update.  The full step must be rejected, while
   * repeated binary backtracking must find a realizable state without
   * modifying the live solution.
   */
  std::vector<su2double> rhos = {
      3.61081e-8,
      7.0e-4,
      2.0e-4,
      2.0e-5,
      4.0e-5,
      4.0e-5,
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_11", true, rhos);

  constexpr unsigned long nDim = 2;
  const unsigned long nSpecies = rhos.size();
  const unsigned long nVar = nSpecies + nDim + 2;
  const unsigned long nPrimVar = nSpecies + nDim + 10;
  const unsigned long nPrimVarGrad = nSpecies + nDim + 8;

  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 12000.0;
  const su2double Tve = 9000.0;

  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);
  const su2double pressure = fluid_model.ComputePressure();

  su2double rho = 0.0;
  for (const auto rho_i : rhos)
    rho += rho_i;

  std::vector<su2double> massfrac(nSpecies, 0.0);
  for (size_t i = 0; i < nSpecies; ++i)
    massfrac[i] = rhos[i] / rho;

  const su2double mach[nDim] = {0.0, 0.0};

  CNEMONSVariable nodes(
      pressure,
      massfrac.data(),
      mach,
      T,
      Tve,
      1,
      nDim,
      nVar,
      nPrimVar,
      nPrimVarGrad,
      config.get(),
      &fluid_model);

  REQUIRE_FALSE(nodes.SetPrimVar(0, &fluid_model));

  std::vector<su2double> U0(nVar, 0.0);
  for (size_t i = 0; i < nVar; ++i)
    U0[i] = nodes.GetSolution(0, i);

  const unsigned long energy_index = nSpecies + nDim;

  REQUIRE(U0[energy_index] > 0.0);

  std::vector<su2double> deltaU(nVar, 0.0);

  /*
   * Make alpha=1 grossly inadmissible.  As alpha -> 0 the trial state
   * approaches the already valid U0, so binary backtracking must
   * eventually find a valid state.
   */
  deltaU[energy_index] = -2.0 * U0[energy_index];

  const su2double alpha =
      nodes.ComputeAdmissibleImplicitStep(
          0,
          deltaU.data(),
          1.0,
          &fluid_model,
          24);

  CAPTURE(alpha);

  REQUIRE(alpha > 0.0);
  REQUIRE(alpha < 1.0);

  /*
   * The accepted trial returned by the limiter must be thermochemically
   * realizable.
   */
  std::vector<su2double> Utrial = U0;

  for (size_t i = 0; i < nVar; ++i)
    Utrial[i] += alpha * deltaU[i];

  std::vector<su2double> Vtrial(nPrimVar, 0.0);
  std::vector<su2double> dPdU(nVar, 0.0);
  std::vector<su2double> dTdU(nVar, 0.0);
  std::vector<su2double> dTvedU(nVar, 0.0);
  std::vector<su2double> eves(nSpecies, 0.0);
  std::vector<su2double> Cvves(nSpecies, 0.0);

  Vtrial[nodes.GetTIndex()] = nodes.GetTemperature(0);
  Vtrial[nodes.GetTveIndex()] = nodes.GetTemperature_ve(0);

  REQUIRE_FALSE(
      nodes.Cons2PrimVar(
          Utrial.data(),
          Vtrial.data(),
          dPdU.data(),
          dTdU.data(),
          dTvedU.data(),
          eves.data(),
          Cvves.data()));

  REQUIRE(std::isfinite(Vtrial[nodes.GetTIndex()]));
  REQUIRE(std::isfinite(Vtrial[nodes.GetTveIndex()]));
  REQUIRE(Vtrial[nodes.GetTIndex()] > 0.0);
  REQUIRE(Vtrial[nodes.GetTveIndex()] > 0.0);

  /*
   * The helper is a trial-state calculation only.  It must not modify
   * the live conservative solution.
   */
  for (size_t i = 0; i < nVar; ++i)
    CHECK(nodes.GetSolution(0, i) == Approx(U0[i]));
}


TEST_CASE(
    "Mutation++ AIR-7 implicit chemistry Jacobian matches finite differences",
    "[Mutation++][NEMO][chemistry][air7]") {

  const std::vector<su2double> rhos = {
      1.0e-12,
      7.0e-4,
      2.0e-4,
      2.0e-5,
      4.0e-5,
      4.0e-5,
      1.0e-10
  };

  CheckMutationChemistryJacobian(
      "air_7", true, rhos, {1, 2, 4, 5});

  CheckMutationEveSourceJacobian(
      "air_7", true, rhos, {1, 2, 4, 5});
}



TEST_CASE(
    "NEMO ionized gamma uses heavy-particle translational gas constant",
    "[Mutation++][NEMO][gamma][air11]") {

  /*
   * AIR-11 ordering:
   * e-, N+, O+, NO+, N2+, O2+, N, O, NO, N2, O2.
   *
   * Use a deliberately visible electron density so inclusion of the
   * electron gas constant in the numerator cannot hide in roundoff.
   */
  std::vector<su2double> rhos = {
      1.0e-8,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  auto config = MakeMutationConfig("air_11", true, rhos);

  constexpr unsigned short nDim = 2;
  CMutationTCLib fluid_model(config.get(), nDim);

  const su2double T = 12000.0;
  const su2double Tve = 9000.0;
  fluid_model.SetTDStateRhosTTv(rhos, T, Tve);

  const auto& molar_mass = fluid_model.GetSpeciesMolarMass();
  const auto& cvtr = fluid_model.GetSpeciesCvTraRot();

  REQUIRE(molar_mass.size() == rhos.size());
  REQUIRE(cvtr.size() == rhos.size());

  su2double rhoCvtr = 0.0;
  su2double rhoR_heavy = 0.0;
  const su2double Ru = 1000.0 * UNIVERSAL_GAS_CONSTANT;

  /* Electron is index 0; translational heavy-particle gamma excludes it. */
  for (size_t i = 1; i < rhos.size(); ++i) {
    rhoCvtr += rhos[i] * cvtr[i];
    rhoR_heavy += rhos[i] * Ru / molar_mass[i];
  }

  REQUIRE(rhoCvtr > 0.0);

  const su2double expected_gamma = 1.0 + rhoR_heavy / rhoCvtr;
  const su2double computed_gamma = fluid_model.ComputeGamma();

  CAPTURE(expected_gamma, computed_gamma);
  CHECK(computed_gamma ==
        Approx(expected_gamma).epsilon(1.0e-12).margin(1.0e-12));
}


TEST_CASE(
    "Mutation++ AIR-11 implicit chemistry Jacobian matches finite differences",
    "[Mutation++][NEMO][chemistry][air11]") {

  const std::vector<su2double> rhos = {
      1.0e-12,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      1.0e-9,
      4.0e-5,
      4.0e-5,
      2.0e-5,
      7.0e-4,
      2.0e-4
  };

  CheckMutationChemistryJacobian(
      "air_11", true, rhos, {6, 7, 9, 10});

  CheckMutationEveSourceJacobian(
      "air_11", true, rhos, {6, 7, 9, 10});
}

#endif
/* MUTATIONPP_IMPLICIT_CHEM_JAC_TEST_END */
