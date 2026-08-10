# Excel-lence Data Validator

An automated actuarial and insurance data validation engine built in R. It uses **Google Gemini AI** for schema inference and rule generation, coupled with a **deterministic R execution engine** for error reporting.

---

## 🌟 Architecture Overview

```
Input Data (.xlsx) ──► Schema Generator (AI) ──► Data Cleaning ──► Rules Generator (AI) ──► Rules Engine (Pure R) ──► Output Report (.xlsx)
```

1. **Data Schema Generator**: Uses Gemini AI (`ellmer`) to analyze raw dataset structures and output `Output/Data_Schema.xlsx`.
2. **Data Cleaning & Standardization**: Cleans raw data and parses date strings (handling Excel serial dates like `44629` and formatted strings) and numeric types based on `Data_Schema.xlsx`.
3. **Validation Rules Generator**: Uses Gemini AI to construct a comprehensive list of single-column, cross-column, and cross-table validation rules saved in `Output/Validation_Rules.xlsx`.
4. **Deterministic Rules Engine**: Executes the generated rules against datasets using vector-optimized R validator functions without requiring AI for execution.
5. **Report Generation**: Exports detailed error logs including row indices, VINs, invalid values, and comparison values to `Output/Validation_Report.xlsx`.

---

## 🛠️ Supported Rule Types

| Rule Type | Description | Inputs / Parameters |
| :--- | :--- | :--- |
| **`missing`** | Flags null, NA, or empty string values. | `Column 1` |
| **`unique`** | Flags duplicate entries in primary key columns. | `Column 1` |
| **`positive`** | Flags numbers $\le 0$. | `Column 1` |
| **`range`** | Flags values falling outside numeric bounds. | `Column 1`, `Parameter`: `"min, max"` |
| **`greater_than`** | Checks if `Column 1 > Column 2` (same table or cross-table join). | `Column 1`, `Column 2`, optional `Table 2` |
| **`equals`** | Checks if `Column 1 == Column 2` (same table or cross-table join). | `Column 1`, `Column 2`, optional `Table 2` |
| **`exists`** | Foreign key check (verifies `Column 1` values exist in `Table 2`). | `Column 1`, `Table 2`, `Column 2` |
| **`allowed_values`** | Flags categorical values not in the allowed domain list (ignores leading/trailing whitespace). | `Column 1`, `Parameter`: `"val1, val2, val3"` |

---

## 🚀 Getting Started

### Prerequisites

- R (v4.0 or higher)
- Google Gemini API Key configured in your R environment (`.Renviron`):
  ```env
  GEMINI_API_KEY="your-api-key-here"
  Excel_lence_Path="e:/Dev Projects/Excel_lence_data_validator"
  ```

### Required R Packages

```r
install.packages(c("readxl", "ellmer", "jsonlite", "writexl", "lubridate"))
```

### Folder Structure

```
Excel_lence_data_validator/
├── Codes/
│   └── R_data_Validator.R         # Main pipeline script
├── Input/
│   ├── EV_Vehicle_Sales_Data_500.xlsx
│   └── EV_Warranty_Claims_Synthetic_Flawed_150-1.xlsx
├── Output/
│   ├── Data_Schema.xlsx           # Generated dataset schema
│   ├── Validation_Rules.xlsx      # Generated (and editable) validation rules
│   └── Validation_Report.xlsx     # Final validation error report
└── README.md
```

---

## ⚙️ Running the Validation Pipeline

Run the pipeline from your R console or RStudio:

```r
source("Codes/R_data_Validator.R")
```

---

## 📊 Output Files

1. **`Output/Data_Schema.xlsx`**: Detailed metadata, data types, and business descriptions for all columns.
2. **`Output/Validation_Rules.xlsx`**: Structured validation rules. You can review, edit, or add custom rules here before re-running the engine!
3. **`Output/Validation_Report.xlsx`**: Comprehensive error log listing:
   - `Rule ID` & `Severity`
   - `Table 1` & `Row Index`
   - `VIN` (Vehicle Identification Number)
   - `Column 1` & `Value 1`
   - `Column 2` & `Value 2` (for comparison rules)
   - Rule `Description`
