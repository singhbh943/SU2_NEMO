/*!
 * \file CMutationTCLib.hpp
 * \brief Defines the class for the link to Mutation++ ThermoChemistry library.
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

#pragma once

#include "CNEMOGas.hpp"

#if defined(HAVE_MPP) && !defined(CODI_REVERSE_TYPE) && !defined(CODI_FORWARD_TYPE)
#include "mutation++.h"
#include <limits>

/*!
 * \derived class CMutationTCLib
 * \brief Child class for Mutation++ nonequilibrium gas model.
 * \author:  C. Garbacz
 */
class CMutationTCLib : public CNEMOGas {

private:

  std::unique_ptr<Mutation::Mixture> mix; /*!< \brief Pointer to object Mixture from Mutation++ library. */

  vector<su2double> Cv_ks,                /*!< \brief Species specific heats at constant volume. */
  es,                                     /*!< \brief Species energies. */
  omega_vec;                              /*!< \brief Dummy vector for vibrational energy source term. */

  su2double Tref;                         /*!< \brief Reference temperature. */

public:

  /*!
   * \brief Constructor of the class.
   */
  CMutationTCLib(const CConfig* config, unsigned short val_nDim);

  /*!
   * \brief Destructor of the class.
   */
  virtual ~CMutationTCLib(void);

  /*!
   * \brief Set mixture therodynamic state.
   * \param[in] rhos - Species partial densities.
   * \param[in] T    - Translational/Rotational temperature.
   * \param[in] Tve  - Vibrational/Electronic temperature.
   */
  void SetTDStateRhosTTv(vector<su2double>& val_rhos, su2double val_temperature, su2double val_temperature_ve) final;

  /*!
   * \brief Get species T-R specific heats at constant volume.
   */
  vector<su2double>& GetSpeciesCvTraRot() final;

  /*!
   * \brief Compute species V-E specific heats at constant volume.
   */
  vector<su2double>& ComputeSpeciesCvVibEle(su2double val_T) final;

  /*!
   * \brief Compute the exact local derivative of V-E energy density with
   * respect to Tve for the Mutation++ two-temperature energy definition.
   */
  su2double ComputerhoCvve() final;

  /*!
   * \brief Compute dT/dU using Mutation++'s own two-mode species energies.
   */
  void ComputedTdU(const su2double *V, su2double *val_dTdU) final;

  /*!
   * \brief Compute dP/dU consistently with the Mutation++ two-temperature
   * energy definition.
   */
  void ComputedPdU(const su2double *V,
                   const vector<su2double>& val_eves,
                   su2double *val_dPdU) final;


  /*!
   * \brief Compute mixture energies (total internal energy and vibrational energy).
   */
  vector<su2double>& ComputeMixtureEnergies() final;

  /*!
   * \brief Compute vector of species V-E energy.
   */
  vector<su2double>& ComputeSpeciesEve(su2double val_T, bool vibe_only = false) final;

  /*!
   * \brief Compute species net production rates.
   */
  vector<su2double>& ComputeNetProductionRates(bool implicit, const su2double *V, const su2double* eve,
                                               const su2double* cvve, const su2double* dTdU, const su2double* dTvedU,
                                               su2double **val_jacobian) final;

  /*!
   * \brief Compute vibrational energy source term.
   */
  su2double ComputeEveSourceTerm() final;

  /*!
   * \brief Populate the Mutation++ V-E energy-transfer source Jacobian.
   */
  void GetEveSourceTermJacobian(const su2double *V, const su2double *eve, const su2double *cvve,
                                const su2double *dTdU, const su2double *dTvedU,
                                su2double **val_jacobian) final;

  /*!
   * \brief Compute species enthalpies.
   */
  vector<su2double>& ComputeSpeciesEnthalpy(su2double val_T, su2double val_Tve, su2double *val_eves) final;

  /*!
   * \brief Get species diffusion coefficients.
   */
  vector<su2double>& GetDiffusionCoeff() final;

  /*!
   * \brief Compute Mutation++ generalized Stefan-Maxwell diffusion
   *        velocities and ambipolar electric field.
   */
  bool ComputeStefanMaxwellDiffusionVelocities(
      const vector<su2double>& val_grad_rhos,
      su2double val_grad_T,
      su2double val_grad_Tve,
      vector<su2double>& val_diffusion_velocity,
      su2double& val_ambipolar_electric_field) final;

  /*!
   * \brief Get viscosity.
   */
  su2double GetViscosity() final;


  /*!
   * \brief Get T-R and V-E thermal conductivities vector.
   */
  vector<su2double>& GetThermalConductivities() final;

  /*!
   * \brief Compute translational and vibrational temperatures vector.
   */
  vector<su2double>& ComputeTemperatures(vector<su2double>& val_rhos, su2double rhoE, su2double rhoEve, su2double rhoEvel, su2double Tve_old) final;

  /*
   * Mutation++ performs its own thermochemical inversion and the SU2
   * closure checks validate the returned state. Do not impose the
   * native SU2-TC 80000 K ceiling on this backend.
   */
  su2double GetMaximumTemperature() const final {
    return std::numeric_limits<su2double>::infinity();
  }

  su2double GetMaximumVETemperature() const final {
    return std::numeric_limits<su2double>::infinity();
  }

  /*!
   * \brief Get species molar mass.
   */
  vector<su2double>& GetSpeciesMolarMass() final;

  /*!
   * \brief Get reference temperature.
   */
  vector<su2double>& GetRefTemperature() final;

  /*!
   * \brief Get species formation enthalpy.
   */
  vector<su2double>& GetSpeciesFormationEnthalpy() final;

};
#endif
