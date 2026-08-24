# Multi-Domain AD Group Membership Audit Script

AD Group Membership Validation is a PowerShell utility that audits Active Directory group memberships across multiple domains using **EmployeeID** as the unique identifier.

The script:

- Reads EmployeeIDs from a CSV file
- Reads target AD groups from a CSV file
- Searches users across multiple domains
- Caches group memberships for improved performance
- Validates user membership against every specified group
- Exports results to a timestamped CSV report

---

## Features

✅ Multi-domain Active Directory support

✅ EmployeeID-based user lookup

✅ Cached membership validation for faster processing

✅ Automatic CSV report generation

✅ Handles missing users gracefully

✅ Dynamic reporting across multiple groups and domains

✅ GitHub and enterprise-ready structure

---

## Requirements

### Software

- Windows PowerShell 5.1 or later
- Active Directory PowerShell Module
- Domain connectivity to all target domains

### PowerShell Module

```powershell
Import-Module ActiveDirectory
```

---

## Input Files

Place the following files in the same folder as the script.

### User Input File

**File Name**

```text
ip_GetADGroupMember.csv
```

**Format**

```csv
EmployeeID
123456
234567
345678
```

---

### Group Input File

**File Name**

```text
ip_Groups.csv
```

**Format**

```csv
GroupName,GroupDomain
Domain Admins,contoso.com
VPN Users,fabrikam.com
Azure Sync Team,child.contoso.com
```

---

## Folder Structure

```text
ADGroupMembershipValidation
│
├── ADGroupMembershipValidation.ps1
├── ip_GetADGroupMember.csv
├── ip_Groups.csv
└── op_GetADGroupMember_MM-DD-YYYY_HHMMSS.csv
```

---

## Configuration

By default the script searches Active Directory using:

```powershell
$EmployeeIDAttribute = "EmployeeID"
```

If your organization stores the identifier in another attribute, update:

```powershell
$EmployeeIDAttribute = "CustomID"
```

or any supported AD attribute name.

---

## How It Works

### Step 1

Load EmployeeIDs from:

```text
ip_GetADGroupMember.csv
```

### Step 2

Load Group Names and Domains from:

```text
ip_Groups.csv
```

### Step 3

Cache all group memberships.

### Step 4

Search users across supplied domains.

### Step 5

Validate membership using cached Distinguished Names.

### Step 6

Generate final audit report.

---

## Sample Output

```csv
EmployeeID,UserName,[contoso.com] Domain Admins,[fabrikam.com] VPN Users
123456,John Smith,Present,Not Present
234567,Sarah Jones,Not Present,Present
345678,User Not Found,Not Present,Not Present
```

---

## Output File

The report is automatically generated with a timestamp:

```text
op_GetADGroupMember_08-24-2026_103522.csv
```

---

## Error Handling

The script handles:

- Missing input files
- Empty CSV files
- Invalid group names
- Failed domain lookups
- Missing users
- AD query exceptions

Warnings are displayed in the console without terminating the entire audit process.

---

## Performance Notes

For large environments:

- Group memberships are cached once
- Users are searched in batches
- Duplicate EmployeeIDs are removed automatically
- Domain lookups are minimized

This significantly improves performance compared to querying membership individually for every user.

---

## Security Considerations

- Read-only Active Directory operations
- No modifications are made to users or groups
- Requires only permissions necessary to query Active Directory

---

## Version History

### 2.0.0

- Renamed WorkforceID to EmployeeID
- Added configurable AD attribute support
- Improved validation and error handling
- Added strict mode
- Improved code readability
- Updated documentation

### 1.0.0

- Initial release

---

## Author

**Saeed Rather**

Security Analysis Analyst

---

## License

This project is intended for internal enterprise administration and auditing purposes.

Modify and distribute according to your organization's policies.
