# Labrat: A Cheesy bringup testlab for Chrome OS

cros-labrat is a loose collection of scripts that can help Chrome OS developers manage a small fleet of machines during bringup.
For Googlers, checkout the design doc at [go/cros-labrat](https://goto.google.com/cros-labrat).

Things labrat can help you do:
 * Deploy the latest AP firmware and OS image to your devices.
 * Run a suite of tests across your devices, and upload results to a Google Storage bucket (possibly shared with team members or partners).
 * Scrape the GS bucket and present a dashboard of test results.

There is no server side, and there is no daemon. Only write access to a GS bucket is needed. It should be easy enough for partners to get set up and contribute to the test results pool as well.

## Getting Started

Labrat gets its configuration by default from configs/default.json.
 * Copy configs/sample.json to configs/default.json, and edit it to your liking:
   * Add the IP addresses of the machines you want to manage.
   * Add the GS bucket location results should be uploaded to.
   * Add the set of tests you want to run.
 * You can create multiple configurations in this directory (for different pools or suites), and pass --config=myconfig to use configs/myconfig.json.

Task scripts can be run individually, or combined with the for_all_duts.sh script to run across all devices.

## Examples

Update the AP firmware to the latest on a single device:
```
./update_firmware.sh --remote=192.168.1.102
```

Update the OS build to a specific version on a single device:
```
./update_os.sh --remote=182.168.1.102 --buildnum=13416.0.0
```

Update the OS to the latest from GoldenEye on all devices listed in configs/default.json:
```
./for_all_duts.sh ./update_os.sh
```
