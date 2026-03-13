# Ryan's Script Collection

A personal collection of Bash, Python, and PowerShell scripts used to automate tasks, monitor system health, and manage workflows on Linux and Windows machines.

## 📂 Repository Structure

| Directory         | Description                                                                                                                                                   |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Archive/**      | Old or deprecated scripts that are no longer in active use.                                                                                                   |
| **AutoShutdown/** | Automatically shuts down the laptop after 30 minutes of idle time on battery power to save energy.                                                            |
| **BashWeather/**  | Sets a `WEATHERCHAR` environment variable with an emoji based on current weather (via OpenWeatherMap API).                                                    |
| **BitLocker/**    | PowerShell script to ensure BitLocker is properly configured on the system drive, add TPM protector, and escrow the recovery password to Entra ID (Azure AD). |
| **Convert/**      | Tools for file format conversion.                                                                                                                             |
| **Health/**       | Monitors system health including battery status, SMART disk health, USB devices, and temperatures.                                                            |
| **OpenMinimize/** | Scripts to launch applications (like email or task managers) and immediately minimize them to the background.                                                 |
| **Temperature/**  | Automated screen color temperature adjustment based on time of day (similar to f.lux).                                                                        |
| **Verify/**       | Utilities for file verification and data validation.                                                                                                          |

## 🚀 Setup & Usage

### BashWeather Configuration

The scripts in `BashWeather` require an API key to function.

1. Get a free API key from [OpenWeatherMap](https://openweathermap.org/).
2. Export it in your shell environment (e.g., in `~/.bashrc`):
   ```bash
   export OPEN_WEATHER_API_KEY="your_api_key_here"
   ```

### BitLocker Remediation Script

The `BitLocker/bitlocker-escrow.ps1` script performs the following actions on the system drive (C:):

- Ensures a BitLocker recovery password exists and escrows it to Entra ID (Azure AD).
- Adds a TPM-based key protector if missing (initializes TPM if needed).
- Resumes BitLocker protection if it is suspended.

**Requirements:**

- Windows 10/11 Pro or Enterprise (or other edition with BitLocker support).
- TPM (Trusted Platform Module) present and enabled.
- The machine must be joined to Entra ID (Azure AD) for key escrow to succeed.
- Run the script with administrator privileges (it auto-elevates if not already).

**Usage:**

Simply run the script from an elevated PowerShell prompt:

```powershell
.\bitlocker-escrow.ps1
```

All actions are logged to `BitLocker-Remediation.log` in the same directory as the script. Exit code `0` indicates success, `1` indicates failure.
