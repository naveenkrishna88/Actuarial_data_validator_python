# Excel_lence_data_validator
This project is an actuarial data validation pipeline that loads Sales.xlsx and Claims.xlsx, performs standardization and deterministic checks, and produces a single Excel validation report.

## Usage
1. Place `Sales.xlsx` and `Claims.xlsx` into the `Input/` folder.
2. Optionally set `Excel_lence_Path` in your environment to the repository root.
3. Run the main script:

```r
source("Codes/R_data_Validator.R")
```

## Output
- `Output/Validation_Report.xlsx`
- Includes summary metrics, Sales/Claims/Cross-file issues, AI-generated questions, and executive summary.

## Notes
- The script standardizes dates, trims text, uppercases IDs, and converts numeric fields.
- AI output is enabled when `GEMINI_API_KEY` is set in the environment.
- The current version assumes fixed file names for the MVP.
