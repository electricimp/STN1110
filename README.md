# STN1110 #

This library provides an interface to the [STN1110](https://www.scantool.net/stn1110.html) Multiprotocol OBD-II to UART Interpreter.

- [STN1110 Reference Manual](https://www.scantool.net/scantool/downloads/98/stn1100-frpm.pdf)
- [List of OBD-II PIDs](http://en.wikipedia.org/wiki/OBD-II_PIDs)

### Classes ###

Two classes are implemented for interacting with the STN1110 over UART.

1. STN1110 is a low-level wrapper for executing commands over UART and reading back results from the STN1110.
3. VehicleInterface is a high-level interface for accessing common vehicle data like speed, RPM, temperatures or other arbitrary OBD-II PIDs.

### Examples ###

An example utilizing VehicleInterface and the Plotly library is provided. The [Plotly example](examples/plotly) logs several vehicle parameters over time and generates a plotly graph of their values.

Short examples for each class are provided below.

#### VehicleInterface ####

```squirrel
car <- VehicleInterface(hardware.uart57);
// logs vehicle speed once per second
car.subscribe(car.VEHICLE_SPEED, function(result) {
  if ("err" in result) {
    server.error("Error getting vehicle speed");
    return;
  }
  server.log("Current speed: " + result["msg"] + "km/h")
}, 1);
```

#### STN1110 ####

```squirrel
stn1110 <- STN1110(hardware.uart57)
stn1110.execute("AT@1", 1, function(result) { // AT@1 command returns device description string
	if ("err" in result) {
    server.error("Error executing command")
    return
	}
	server.log("Device description: " + result["msg"])
})
```

## VehicleInterface Class Usage ##

### Constructor(*uart[, baud]*) ###

To instantiate the class, pass in the [imp UART](https://developer.electricimp.com/api/hardware/uart/) that the STN1110 is connected to. The UART will be reconfigured by the constructor for communication with the STN1110. This is a blocking call that will return when the STN1110 interface is ready to use. This method may throw an exception if initializing the device fails or times out. The optional baud parameter can be used for initial connection if the STN1110 has a baud rate other than the default 9600 stored in its EEPROM.

## VehicleInterface Class Methods ##

### read(*pid, callback*) ###

Reads a PID once and executes callback with the resulting data. If the PID is in the list of supported PIDs, the callback will be called with a single value in the correct units. If the PID is not supported the callback will be called with a byte array containing the raw result of the request.

### subscribe(*pid, callback, period*) ###

Reads a PID every 'period' seconds and executes callback with the resulting data. If the PID is in the list of supported PIDs, the callback will be called with a single value in the correct units. If the PID is not supported the callback will be called with a byte array containing the raw result of the request.

### unsubcribe(*pid*) ###

Unsubscribes the callback, if any, for PID *pid* and stops requesting the PID.

#### Supported PIDs ####

- *VehicleInterface.ENGINE_RPM* &mdash; The engine's RPM in units RPM.
- *VehicleInterface.VEHICLE_SPEED* &mdash; Get the vehicle speed in units km/h.
- *VehicleInterface.THROTTLE_POSITION* &mdash; The throttle position as a percentage.
- *VehicleInterface.COOLANT_TEMPERATURE* &mdash; The engine coolant temperature in degrees celsius.
- *VehicleInterface.FUEL_PRESSURE* &mdash; The fuel pressure in kPa.
- *VehicleInterface.INTAKE_AIR_TEMPERATURE* &mdash; The intake air temperature in degrees celsius.
- *VehicleInterface.ENGINE_RUNTIME* &mdash; The runtime since engine start in minutes.

## STN1110 Class Usage ##

### Constructor(*uart[, baud]*) ###

To instantiate the class, pass in the [imp UART](https://developer.electricimp.com/api/hardware/uart/) that the STN1110 is connected to. The UART will be reconfigured by the constructor for communication with the STN1110. This is a blocking call that will return when the STN1110 interface is ready to use. This method may throw an exception if initializing the device fails or times out. The optional baud parameter can be used for initial connection if the STN1110 has a baud rate other than the default 9600 stored in it's EEPROM.

## STN1110 Class Methods ##

### STN1110.execute(*command, timeout, callback*) ###

Executes the command string *command* with timeout *timeout* seconds and calls *callback* with the result. Callback is called with one parameter that is a table containing either an *err* key or a *msg* key. If the *err* key is present in the table an error occured during command execution and the corresponding value describes the error. If the *err* key is not present in the table the *msg* value will contain the output of the command.

### reset() ###

Performs a soft reset of the STN1110. This is a blocking call that will return when the STN1110 interface is ready to use. This method may throw an exception if initializing the device fails or times out.

### setBaudRate(baud) ###

Sets the baud rate to *baud*. This is a blocking call, when it returns the STN1110 is now operating at the new baud rate, unless an exception is thrown. Exceptions will be thrown if commands are currently executing, if the baud rate is deemed invalid by the STN1110 or if another error occurs while setting the baud rate.

### getBaudRate() ###

Returns the baud rate the uart interface is currently operating at.

### getElmVersion() ###

Returns the version string of the ELM emulator provided by the STN1110 on reset.

### onError(*callbac*k) ###

Pass a callback function to be called if an error occurs after initialization and no PID callbacks are registered to receive the error.

## License ##

The STN1110 library is licensed under the [MIT License](./LICENSE).
