# TeamViewer Web API example scripts

[![CI](https://github.com/teamviewer/api-example-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/teamviewer/api-example-scripts/actions/workflows/ci.yml)

A continously growing set of Powershell example scripts that showcase the
[TeamViewer Web API](https://www.teamviewer.com/en/for-developers/).

## Contents

### [Add-SsoExclusionsFromCSV](./Add-SsoExclusionsFromCSV)

* 📜 Adds users from a CSV file to the TeamViewer SSO exclusion list of their respective domain.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed

### [Set-TeamViewerDevicesPolicy](./Set-TeamViewerDevicesPolicy)

* 📜 Sets the policy for all / specific devices to specific policy or inherits policy from group.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed

### [Remove-TeamViewerOutdatedDevice](./Remove-TeamViewerOutdatedDevice)

* 📜 Removes TeamViewer devices (MDv1) that didn't appear online for a given time.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed

### [Remove-TeamViewerOutdatedDeviceV2](./Remove-TeamViewerOutdatedDeviceV2)

* 📜 Removes TeamViewer devices (MDv2) that didn't appear online for a given time.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed

### [Import-TeamViewerUser](./Import-TeamViewerUser):

* 📜 Imports and updates a set of users from a CSV file into the TeamViewer company.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed

### [Invoke-TeamViewerGroupPerUserSync](./Invoke-TeamViewerGroupPerUserSync)

* 📜  Moves devices from a common group to a shared group per user.
* ⚙️ [TeamViewerPS](https://github.com/teamviewer/TeamViewerPS) module needed
