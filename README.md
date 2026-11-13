# Sewer Heat Transfer Model

## Overview

This repository contains a MATLAB-based sewer heat transfer model developed to simulate:

* **Heat availability** in sewer networks.
* **Heat extraction** from sewer networks.

The model couples hydraulic and thermal information to estimate wastewater temperatures and recoverable heat within sewer systems.

The repository includes a complete example simulation for **February**, together with supporting data for other seasons, validation results, and optional Python code for generating the pipe calculation order used by the MATLAB model.

A minimum wastewater temperature constraint of **5 °C** is implemented within the model to prevent unrealistic cooling of wastewater during simulations.

---

## Repository Contents

This repository contains:

* MATLAB code for sewer heat transfer simulations.
* Example input files for a February simulation.
* Example validation results for both **heat availability** and **heat extraction** simulations.
* Supporting data, including monthly wastewater temperature profiles, model parameters, external temperature inputs, and InfoWorks export files used to generate model inputs.
* Optional Python code for generating pipe calculation order file from exported InfoWorks network data.

---

## Repository Structure

```text
SewerHeatTransferModel/
│
├── SewerHeatTransfer_Main.m
├── MATLAB function files (.m)
├── MATLAB data files (.mat)
├── WastewaterTemperature_Feb.csv
│
├── ValidationResults/
│   ├── Availability_Feb/
│   └── Extraction_Feb/
│
├── SupportingData/
│   ├── MonthlyWastewaterTemperature/
│   ├── ParameterTables/
│   │   └── parameter_table.xlsx
│   └── InfoWorksInput_csv/
│
├── Python code_ PipeOrdering/
│
├── README.md
└── .gitignore
```

---

## Main Files

* `SewerHeatTransfer_Main.m` – Main simulation script.
* MATLAB function files (`.m`) – Supporting functions called by `SewerHeatTransfer_Main.m`.

---

## Input Files

The repository includes the input files required to run the example February simulation, including:

* MATLAB data files (`.mat`) containing hydraulic and sewer network data.
* `WastewaterTemperature_Feb.csv`, containing a 48-hour hourly wastewater temperature profile for February.

The February simulation is provided as a complete working example.

---

## Supporting Data

The `SupportingData` folder contains supplementary information for performing simulations for other seasons.

### Monthly Wastewater Temperature Profiles

The folder:

```text
SupportingData/MonthlyWastewaterTemperature/
```

contains 48-hour hourly wastewater temperature profiles for each month of the year.

These profiles were derived from wastewater temperature measurements collected in two study areas and are provided to support simulations for different seasons.

### Parameter Tables

The file:

```text
SupportingData/ParameterTables/parameter_table.xlsx
```

contains:

* Model parameter values.
* External temperature inputs.
* Supporting references.

The workbook includes:

* **Model Parameters** – Recommended parameter values adopted from published literature.
* **External Temperature Inputs** – Monthly values for:

  * In-sewer air temperature,
  * Soil temperature,
  * Infiltration temperature.

The in-sewer air temperature values are based on measured sewer air temperatures.

Users should review the parameter values and refer to the cited literature before applying the model to different sewer systems or operating conditions.

### InfoWorks Input Files

The folder:

`SupportingData/InfoWorksInput_csv/`

contains the exported InfoWorks network data files (.csv) used to generate the corresponding MATLAB input files (.mat) used by the model.

---

## Python code

The folder:

```text
Python code_ PipeOrdering/
```

Contains optional Python script used to generate the pipe calculation order file required by the MATLAB model.

This file is generated from network data exported from InfoWorks using the supplied Python script.

The repository includes an example pipe calculation order file that can be used directly for the supplied example network.

Users wishing to apply the model to a different sewer network should generate a new pipe calculation order file using the Python code.


---

## Running the Model

1. Open MATLAB.
2. Navigate to the repository folder.
3. Open `SewerHeatTransfer_Main.m`.
4. Select the simulation mode:

```matlab
simulationMode = "availability";
```

or

```matlab
simulationMode = "extraction";
```
5. Set the export tag used to identify a simulation and is appended to generated output file and folder names.

```matlab
exportTag = "Feb";
```
6. If running an extraction simulation, define:

   * Heat extraction pipe index (or indices),
   * Required heat extraction rate,
   * Minimum allowable wastewater temperature at the extraction location.
   
7. Modify any required parameter values.

8. Run `SewerHeatTransfer_Main.m`.

---

## Simulation Period and Temperature Stabilisation

To reduce the influence of initial conditions and allow sewer temperatures to stabilise, the hydraulic and thermal input data are repeated for multiple simulation cycles.

The default configuration uses:

* One input cycle of 48 hours.
* Two repeated cycles (`nCycles = 2`).
* A total simulation period of 96 hours.

The first cycle is used primarily for model stabilisation.

Results should generally be interpreted using the final 48-hour cycle, which represents the converged thermal conditions.

Users may modify the value of `nCycles` if longer stabilisation periods are required.

---

## Outputs

Simulation output files are written automatically to a results folder created by the model.

For heat availability simulations, the output folder is created as:

```text
HeatAvailability_<exportTag>
```

For heat extraction simulations, the output folder is created as:

```text
HeatExtraction_<exportTag>
```

Typical output files include:

### Heat Availability Simulation

* `Heat_Inlet_<exportTag>.csv`
* `Heat_Outlet_<exportTag>.csv`
* `Temperature_Inlet_<exportTag>.csv`
* `Temperature_Outlet_<exportTag>.csv`
* `Flow_Inlet_<exportTag>.csv`
* `Flow_Outlet_<exportTag>.csv`

### Heat Extraction Simulation

* `Temperature_Inlet_BeforeExtraction_<exportTag>.csv`
* `Temperature_Inlet_AfterExtraction_<exportTag>.csv`
* `Temperature_Outlet_AfterExtraction_<exportTag>.csv`
* `Extracted_Heat_<exportTag>.csv`


---

## Validation Results

The repository includes example validation results for both:

* **Heat Availability** simulations.
* **Heat Extraction** simulations.

These results are provided to allow users to verify that the model is functioning correctly after installation and before applying the model to other case studies.

---

## Pipe Thermal Conductivity

Default thermal conductivity values for common sewer pipe materials are implemented directly within the MATLAB code. Users may modify these values if alternative material properties are required.

---

## Requirements

The model requires:

* MATLAB (tested with recent MATLAB releases).
* Input hydraulic and network data.
* Wastewater temperature data.

Python is only required if the optional pipe ordering script is used.
---

## Development and Contributions

The Sewer Heat Transfer Model was orginally developed by Dr.Mohamad Abdel-Aal, University of Exeter, UK and subsequently updated and extended by Dr. Alemtsehay Seyoum, University of Sheffield, UK. 

---

## References

Model parameter values, environmental temperature inputs, and other supporting data are based on published literature sources, which are provided in `parameter_table.xlsx`.

Please cite the relevant literature sources when using the parameter values provided in this repository.
