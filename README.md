# STN1110

This library provides several levels of interfaces for the [STN1110](https://www.scantool.net/stn1110.html) Multiprotocol OBD-II to UART Interpreter.

- [STN1110 Reference Manual](https://www.scantool.net/scantool/downloads/98/stn1100-frpm.pdf)
- [List of OBD-II PIDs](http://en.wikipedia.org/wiki/OBD-II_PIDs)

### Classes

Three classes are implemented for interacting with the STN1110 over UART with various levels of abstraction.

1. `UARTInterface`: a low level wrapper for executing commands over UART and reading back results
2. `OBDInterface`: a mid level interface for retrieving raw values of OBD-II PIDs
3. `VehicleInterface`: a high level interface for accessing common vehicle data like speed, RPM and temperatures.

## Examples

An example utilizing VehicleInterface and the Plotly library is provided. The [Plotly example](examples/plotly) logs several vehicle parameters over time and generates a plotly graph of their values.

Short examples for each class are provided below

**VehicleInterface**

```squirrel
car <- VehicleInterface(hardware.uart57)
car.getVehicleSpeed(1, function(speed) { // get speed at 1Hz (callback called once per second)
	server.log("Vehicle is currently travelling at " + speed + "km/h")
})
car.onError(function(error) {
	server.error("Error retrieving vehicle data")
})
```

**OBDInterface**

```squirrel
obd <- OBDInterface(hardware.uart57)
read.readPIDOnce(0x015B, function(result) { // PID 015B is hybrid battery pack remaining life
	if("err" in result) {
		server.error("Error reading SOC")
		return
	}
	local A = result["msg"][0] // first byte
	local B = result["msg"][1] // second byte
	local remainingCharge = A*100/255 // convert to percentage
	server.log("Battery SOC is currently " + remainingCharge + "%")
})
```

**UARTInterface**

```squirrel
stn1110 <- OBDInterface(hardware.uart57)
stn1110.execute("AT@1", 1, function(result) { // AT@1 command returns device description string
	if("err" in result) {
		server.error("Error executing command")
		return
	}
	server.log("Device description: " + result["msg"])
})
```

## VehicleInterface Class Usage

### Constructor(uart)
To instantiate the class, pass in the [imp UART](https://electricimp.com/docs/api/hardware/uart/) that the STN1110 is connected to. The UART will be reconfigured by the constructor for communication with the STN1110.

### Class Methods

### VehicleInterface.getEngineRPM(frequency, callback)
Gets the engine's RPM in units RPM. Callback will be called at frequency Hz.

### VehicleInterface.getVehicleSpeed(frequency, callback) 
Get the vehicle speed in units km/h. Callback will be called at frequency Hz.

### VehicleInterface.getThrottlePosition(frequency, callback) 
Gets the throttle position as a percentage. Callback will be called at frequency Hz.

### VehicleInterface.getEngineLoad(frequency, callback) 
Gets the engine load as a percentage. Callback will be called at frequency Hz.

### VehicleInterface.getCoolantTemperature(frequency, callback) 
Gets the engine coolant temperature in degrees celsius. Callback will be called at frequency Hz.

### VehicleInterface.getFuelPressure(frequency, callback) 
Gets the fuel pressure in kPa. Callback will be called at frequency Hz.

### VehicleInterface.getIntakeAirTemperature(frequency, callback) 
Gets the intake air temperature in degrees celsius. Callback will be called at frequency Hz.

### VehicleInterface.getEngineRuntime(frequency, callback) 
Gets the runtime since engine start in minutes. Callback will be called at frequency Hz.

### VehicleInterface.onError(callback)
Pass a callback function to be called if an error or timeout occurs while retrieving vehicle data

## OBDInterface Class Usage

### Constructor(uart)
To instantiate the class, pass in the [imp UART](https://electricimp.com/docs/api/hardware/uart/) that the STN1110 is connected to. The UART will be reconfigured by the constructor for communication with the STN1110.

### Class Methods

### OBDInterface.readPID(pid, frequency, callback)
Reads a PID with hex id 'pid' at 'frequency' hertz calling 'callback' with the result. Callback is called with one parameter that is a table containing either an "err" key or a "msg" key. If the "err" key is present in the table an error occured during command execution and the corresponding value describes the error. If the "err" key is not present in the table the "msg" key will contain a byte array containing the output bytes of the command.

### OBDInterface.readPIDOnce(pid, callback)
Reads a PID with hex id 'pid' calling 'callback' with the result. Callback is called with one parameter that is a table containing either an "err" key or a "msg" key. If the "err" key is present in the table an error occured during command execution and the corresponding value describes the error. If the "err" key is not present in the table the "msg" key will a contain byte array containing the output bytes of the command.

## UARTInterface Class Usage

### Constructor(uart)
To instantiate the class, pass in the [imp UART](https://electricimp.com/docs/api/hardware/uart/) that the STN1110 is connected to. The UART will be reconfigured by the constructor for communication with the STN1110.

### Class Methods

### UARTInterface.execute(command, timeout, callback)
Executes the command string 'command' with timeout 'timeout' seconds and calls 'callback' with the result. Callback is called with one parameter that is a table containing either an "err" key or a "msg" key. If the "err" key is present in the table an error occured during command execution and the corresponding value describes the error. If the "err" key is not present in the table the "msg" value will contain the output of the command.

### UARTInterface.getElmVersion()
Returns the version string of the ELM emulator provided by the STN1110 on reset


## License

The STN1110 library is licensed under the [MIT License](./LICENSE).
