// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT


// Structure representing a command
class Command {
    command = null // command string
    timeout = null // timeout length in seconds
    callback = null // callback function for result or timeout
    _timer = null // internal timer object for cancelling timeouts

    constructor(command, timeout, callback) {
        this.command = command
        this.timeout = timeout
        this.callback = callback
    }
}
// Class for interfacing with an STN1110 over UART
// Enqueues commands and fires callbacks when replies are received or command times out
class UARTInterface {
    _UART_SYNC_READ_TIMEOUT = 100000 // somewhat arbitrary magic number determined empirically, number of uart.read() calls to execute before assuming the UART is dead
    _UART_BAUD = 9600 // UART baud

    _uart = null // UART the STN1110 is connected to
    _buffer = null // uart receive buffer
    _commandQueue = null // queue of Command objects awaiting execution
    _activeCommand = null // the currently executing command
    _initialized = null // constructor completion success flag
    _elmVersion = null // the version of the ELM emulator returned by the STN1110 on reset
    
    // Constructs a new instance of UARTInterface
    // This WILL reset your UART configuration for the supplied uart parameter
    // When this method returns the UART interface is ready to use, unless an error is thrown
    constructor(uart) {
        _initialized = false
        _buffer = ""
        _commandQueue = []
        _uart = uart
        _uart.configure(_UART_BAUD, 8, PARITY_NONE, 1, NO_CTSRTS, _uartCallback.bindenv(this)) // configure uart to 9600 baud
        // reset STN1110
        _uart.write("ATZ\r")
        try {
            // handle inconsistency in output between hard and soft reset
            local echoOrVersion = _readLineSync()
            if(echoOrVersion == "ATZ") {
                _elmVersion = _readLineSync() // it was an echo, read the next line for version
            } else {
                _elmVersion = echoOrVersion // no echo, it's the version
            }
            _uart.write("ATE0\r") // disable echo
            _readLineSync() // read echo of disable echo command
            local response
            if((response = _readLineSync()) != "OK") { // disable echo failed
                throw "Unexpected response when disabling echo '" + response + "'"
            }
            _eatPromptSync() // eat the prompt
        } catch(error) { // likely something timed out
            throw "Error initializing STN1110 UART interface: " + error
        }
        _initialized = true
    }
    // returns the version string of the ELM emulator provided by the STN1110 on reset
    function getElmVersion() {
        return _elmVersion
    }
    // Executes the command string 'command' with timeout 'timeout' seconds and calls 'callback' with the result
    function execute(command, timeout, callback) {
        local cmd = Command(command, timeout, callback)
        _commandQueue.append(cmd)
        if(_activeCommand == null) {
            _executeNextInQueue()
        }
    }
    
    /* Private methods */

    // executes the next command in the queue
    function _executeNextInQueue() {
        if(_commandQueue.len() > 0) {
            _activeCommand = _commandQueue.remove(0)
            _activeCommand._timer = imp.wakeup(_activeCommand.timeout, _handleTimeout.bindenv(this) )
            _uart.write(_activeCommand.command + "\r")
        }
    }
    // clears the active command and cancels its timeout timer
    function _clearActiveCommand() {
        if(_activeCommand == null) {
            return
        }
        imp.cancelwakeup(_activeCommand._timer)
        _activeCommand = null
    }
    // blocks until it reads a > or times out when uart.read() calls exceed _UART_SYNC_READ_TIMEOUT
    function _eatPromptSync() {
        local noDataCount = 0
        while (_uart.read() != '>') {
            noDataCount++
            if(noDataCount > _UART_SYNC_READ_TIMEOUT) {
                throw "UART read timed out while waiting for prompt"
            }
        }
    }
    // blocks until it reads a CR with a non empty preceeding line then returns the line, or times out when uart.read() calls exceed _UART_SYNC_READ_TIMEOUT
    function _readLineSync() {
        _buffer = ""
        local noDataCount = 0
        local char = null
        while ((char = _uart.read()) != '\r') { // read until newline
            if(char != -1) { // data was read
                _buffer += format("%c", char)
                _buffer = strip(_buffer)
            } else { // no data to read
                noDataCount++
                if(noDataCount > _UART_SYNC_READ_TIMEOUT) {
                    throw "UART read timed out while waiting for newline"
                }
            }
        }
        if(_buffer.len() > 0) { // read a line with something on it
            local localBuf = _buffer
            _buffer = ""
            return localBuf
        }
        return _readLineSync() // line was empty, try again
    }
    // UART callback function
    function _uartCallback() {
        if(_initialized) {
            local char = null
            while ((char = _uart.read()) != -1) { // read in buffer
                _buffer += format("%c", char)
            }
            if(_buffer.len() >= 3 && _buffer.slice(_buffer.len() - 3) == "\r\r>") { // check for two newlines and a prompt to indicate command output has finished
                if(_activeCommand != null && _activeCommand.callback != null) { // make sure there is something to call
                    _activeCommand.callback({"msg" : _buffer.slice(0, _buffer.len() - 3)}) // trim the > prompt and execute the callback
                    // execute next command
                    _clearActiveCommand()
                    _executeNextInQueue()
                } else {
                    throw "No callback registered for response '" + _buffer + "'" // got a response with no active command
                }
                _buffer = ""
            }
        }
    }
    // command timeout handler 
    function _handleTimeout() {
        if(_activeCommand != null && _activeCommand.callback != null) {
            _activeCommand.callback({"err": "command '" + _activeCommand.command + "' timed out"}) // callback with error
        }
        _uart.write(0x04) // send EOT char to kill command
        _eatPromptSync() // eat the prompt
        _buffer = "" // clear  buffer
        // execute next command
        _clearActiveCommand()
        _executeNextInQueue()
    }
}

// Provides a higher level interface for accessing OBD-II PID data over the STN1110 UART interface
class OBDInterface extends UARTInterface {
    // reads a PID with hex id 'pid' at 'frequency' hertz calling 'callback' with the result
    function readPID(pid, frequency, callback) {
        readPIDOnce(pid, callback)
        imp.wakeup(1.0/frequency, (function() { readPID(pid, frequency, callback) }).bindenv(this))
    }
    // reads a PID with hex id 'pid' calling 'callback' with the result
    function readPIDOnce(pid, callback) {
        execute(format("%04X", pid), 1, (function(result) { // format command back to hex string and execute
            if("err" in result) {
                callback(result)
                return
            }
            local str_bytes = split(result["msg"], " ")
            local bytes = []
            for(local i = 2; i < str_bytes.len(); i++) { // first two bytes are the PID echoed, ignore them
                bytes.append(this._hexToInt(str_bytes[i])) // convert back to ints
            }
            callback({"msg": bytes})
        }).bindenv(this))
    }
    // converts a hex string to an integer
    function _hexToInt(hex) {
        local result = 0
        local shift = hex.len() * 4
        for(local d=0; d<hex.len(); d++) {
            local digit
            if(hex[d] >= 0x61)
                digit = hex[d] - 0x57
            else if(hex[d] >= 0x41)
                 digit = hex[d] - 0x37
            else
                 digit = hex[d] - 0x30
            shift -= 4
            result += digit << shift
        }
        return result
    }
}
// Provides a high level interface for accessing vehicle data over OBD-II
class VehicleInterface extends OBDInterface {
    _errorCallbacks = null // array of subscribed callbacks for error handling

    function constructor(uart) {
        _errorCallbacks = []
        base.constructor(uart)
    }
    // gets the engine's RPM in units RPM
    function getEngineRPM(frequency, callback) {
        this._getDoubleBytePID(0x010C, frequency, callback, function(A,B) {
                return ((A*256)+B)/4
        })
    }
    // get the vehicle speed in units km/h
    function getVehicleSpeed(frequency, callback) {
        this._getSingleBytePID(0x010D, frequency, callback, function(A) {
                return A
        })
    }
    // gets the throttle position as a percentage
    function getThrottlePosition(frequency, callback) {
        this._getSingleBytePID(0x0111, frequency, callback, function(A) {
                return A*100/255
        })
    }
    // gets the engine load as a percentage
    function getEngineLoad(frequency, callback) {
        this._getSingleBytePID(0x0104, frequency, callback, function(A) {
                return A*100/255
        })
    }
    // gets the engine coolant temperature in degrees celsius
    function getCoolantTemperature(frequency, callback) {
        this._getSingleBytePID(0x0105, frequency, callback, function(A) {
                return A-40
        })
    }
    // gets the fuel pressure in kPa
    function getFuelPressure(frequency, callback) {
        this._getSingleBytePID(0x010A, frequency, callback, function(A) {
                return A*3
        })
    }
    // gets the intake air temperature in degrees celsius
    function getIntakeAirTemperature(frequency, callback) {
        this._getSingleBytePID(0x010F, frequency, callback, function(A) {
                return A-40
        })
    }
    // gets the runtime since engine start in minutes
    function getEngineRuntime(frequency, callback) {
        this._getDoubleBytePID(0x011F, frequency, callback, function(A, B) {
                return (A*256)+B
        })
    }
    // pass a callback function to be called if an error or timeout occurs while retreiving vehicle data
    function onError(callback) {
        this._errorCallbacks.push(callback)
    }
    
    /* Private methods */
    
    // gets a single byte PID, calls transform closure transform(A) then calls callback with the result
    function _getSingleBytePID(pid, frequency, callback, transform) {
        this.readPID(pid, frequency, (function(result) {
            if("err" in result) {
                this._error(result["err"])
            } else {
                callback(transform(result["msg"][0]))
            }
        }).bindenv(this))
    }
    // gets a double byte PID, calls transform closure transform(A, B) then calls callback with the result
    function _getDoubleBytePID(pid, frequency, callback, transform) {
        this.readPID(pid, frequency, (function(result) {
            if("err" in result) {
                this._error(result["err"])
            } else {
                callback(transform(result["msg"][0], result["msg"][1]))
            }
        }).bindenv(this))
    }
    // calls any registered error callbacks
    function _error(msg) {
        if(this._errorCallbacks.len() > 0) {
            foreach(cb in _errorCallbacks) {
                cb(msg)
            }
        }
    }
}

class DynamicLogger {
    _log = {}
    _logUpdated = {}

    function subscribe(key) {
        _logUpdated[key] <- false
        return (function(value) {
            this._log[key] <- value
            this._logUpdated[key] = true
            this._checkAndLog()
        }).bindenv(this)
    }
    function _checkAndLog() {
        foreach(k,v in _logUpdated) {
            if(v == false) {
                return // bail if any values haven't been updated yet
            }
        }
        agent.send("log", _log)
        foreach(k,v in _logUpdated) {
            _logUpdated[k] = false
        }
    }
}

car <- VehicleInterface(hardware.uart57)
dl <- DynamicLogger()


car.getEngineRPM(0.2, dl.subscribe("rpm"))
car.getVehicleSpeed(0.2, dl.subscribe("speed"))
car.getThrottlePosition(0.2, dl.subscribe("throttle"))
car.getEngineRuntime(0.2, dl.subscribe("runtime"))
car.getCoolantTemperature(0.2, dl.subscribe("coolant_temp"))
car.getIntakeAirTemperature(0.2, dl.subscribe("intake_temp"))
car.getFuelPressure(0.2, dl.subscribe("fuel_pressure"))

car.onError(function(err) {
    server.log("Error: " + err)
})