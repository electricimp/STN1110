// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Class for interfacing with an STN1110 over UART
// Enqueues commands and fires callbacks when replies are received or command times out
class STN1110 {
    
    _UART_TIMEOUT = 1; // UART sync read timeout in seconds
    _UART_MAX_BUFFER_LENGTH = 4096; // 4kB max buffer size before an error is thrown
    _NEWLINE = "\r";
    _NEWLINE_CHAR = 0x0D; // '\r' char
    _PROMPT_CHAR = 0x3E; // '>' char
    _END_OF_PACKET = "\r\r>";
    _COMMAND_RESET = "ATZ";
    _COMMAND_DISABLE_ECHO = "ATE0";
    _COMMAND_SET_BAUD_RATE = "STBR";
    _COMMAND_SUCCESS_REPLY = "OK";
    _END_OF_TRANSMISSION = 0x04;
    _PID_REPLY_MODE_OFFSET = 0x40; // PID responses have the mode offset by 0x40 from the request

    _uart = null; // UART the STN1110 is connected to
    _uartCurrentBaud = null; // baud rate the UART is currently running at
    _uartReadTimeoutStart = null; // hardware.millis() that sync read timeouts are measured from
    _buffer = null; // UART recieve buffer
    _commandQueue = null; // queue of Command objects awaiting execution
    _activeCommand = null; // the currently executing command
    _initialized = null; // constructor completion success flag
    _elmVersion = null; // the version of the ELM emulator returned by the STN1110 on reset
    _errorCallback = null; // callback function for errors occuring after initialization
    
    // Constructs a new instance of STN1110
    // This WILL reset your UART configuration for the supplied uart parameter
    // When this method returns the UART interface is ready to use, unless an error is thrown
    // Optional baud parameter can be used for initial connection if the STN1110 has a baud rate
    // other than the default 9600 stored in it's EEPROM
    constructor(uart, baud=9600) {
        _initialized = false;
        _buffer = "";
        _commandQueue = [];
        _uart = uart;
        _uartCurrentBaud = baud;
        _uart.configure(baud, 8, PARITY_NONE, 1, NO_CTSRTS, _uartCallback.bindenv(this)); // configure uart, register callback
        reset(); // reset STN1110
        _initialized = true;
    }

    // Resets the STN1110 and blocks until the STN1110 is ready to accept commands or times out
    function reset() {
        // write reset command
        _uart.write(_COMMAND_RESET + _NEWLINE);
        try {
            // handle inconsistency in output between hard and soft reset
            local echoOrVersion = _readLineSync();
            if(echoOrVersion == _COMMAND_RESET) {
                _elmVersion = _readLineSync(); // it was an echo, read the next line for version
            } else {
                _elmVersion = echoOrVersion; // no echo, it's the version
            }
            _uart.write(_COMMAND_DISABLE_ECHO + _NEWLINE); // disable echo
            _readLineSync(); // read echo of disable echo command
            local response;
            if((response = _readLineSync()) != _COMMAND_SUCCESS_REPLY) { // disable echo failed
                throw "Unexpected response when disabling echo '" + response + "'";
            }
            _eatPromptSync(); // eat the prompt
        } catch(error) { // likely something timed out
            throw "Error initializing STN1110 UART interface: " + error;
        }
    }

    // Returns the version string of the ELM emulator provided by the STN1110 on reset
    function getElmVersion() {
        return _elmVersion;
    }
    
    // Returns the baud rate the uart interface is currently operating at
    function getBaudRate() {
        return _uartCurrentBaud;
    }
    
    // Sets the baud rate to 'baud'.
    // This is a blocking call, when it returns the STN1110 is now operating at the new baud rate, unless an exception is thrown.
    // Errors will be thrown if commands are currently executing, if the baud rate is deemed invalid by the STN1110 or if another exception occurs while setting the baud rate.
    function setBaudRate(baud) {
        if(_activeCommand != null || _commandQueue.len() > 0) {
            throw "Cannot change baud rate while commands are executing"
        }
        _uart.write(_COMMAND_SET_BAUD_RATE + " " + baud + _NEWLINE); // write set baud rate command
        if(_readLineSync() != _COMMAND_SUCCESS_REPLY) { // STN1110 will reply OK if the baud rate is valid
            throw "Error setting baud rate to '" + baud + "'";
        }
        // reconfigure our uart
        _uart.configure(baud, 8, PARITY_NONE, 1, NO_CTSRTS, _uartCallback.bindenv(this)); // reconfigure uart, register callback
        _uart.write(_NEWLINE) // write newline so the STN1110 knows the baud rate change was successful
        _readLineSync() // read STN1110 version string
        if(_readLineSync() != _COMMAND_SUCCESS_REPLY) { // make sure we can receive OK from the STN1110
            // try to restore to previous baud then throw error
            _uart.configure(_uartCurrentBaud, 8, PARITY_NONE, 1, NO_CTSRTS, _uartCallback.bindenv(this));
            throw "Error setting baud rate to '" + baud + "'";
        }
        // everything went well, keep track of the new baud
        _uartCurrentBaud = baud;
    }

    // Executes the command string 'command' with timeout 'timeout' seconds and calls 'callback' with the result
    function execute(command, timeout, callback) {
        local cmd = { 
            "command": command, 
            "timeout": timeout,
            "callback": callback
        };
        _commandQueue.append(cmd);
        if(_activeCommand == null) {
            _executeNextInQueue();
        }
    }

    // Pass a callback function to be called if an error occurs after initialization and no PID callbacks are registered to receive the error
    function onError(callback) {
        _errorCallback = callback;
    }
    
    /* Private methods */

    // executes the next command in the queue
    function _executeNextInQueue() {
        if(_commandQueue.len() > 0) {
            _activeCommand = _commandQueue.remove(0);
            _activeCommand.timer <- imp.wakeup(_activeCommand.timeout, _handleTimeout.bindenv(this));
            _uart.write(_activeCommand.command + _NEWLINE);
        }
    }

    // clears the active command and cancels its timeout timer
    function _clearActiveCommand() {
        if(_activeCommand == null) {
            return;
        }
        imp.cancelwakeup(_activeCommand.timer);
        _activeCommand = null;
    }

    // blocks until it reads a > or times out
    function _eatPromptSync() {
        if(_uartReadTimeoutStart == null) {
            _uartReadTimeoutStart = hardware.millis();
        }
        while (_uart.read() != _PROMPT_CHAR) {
            if((hardware.millis() - _uartReadTimeoutStart) > _UART_TIMEOUT*1000) {
                throw "UART read timed out while waiting for prompt";
            }
        }
    }
    
    // blocks until it reads a CR with a non empty preceeding line then returns the line, or times out
    function _readLineSync() {
        _buffer = "";
        local char = null;
        if(_uartReadTimeoutStart == null) {
            _uartReadTimeoutStart = hardware.millis();
        }
        while ((char = _uart.read()) != _NEWLINE_CHAR) { // read until newline
            if(char != -1) { // data was read
                _buffer += format("%c", char);
                _buffer = strip(_buffer);
            } else {
                if((hardware.millis() - _uartReadTimeoutStart) > _UART_TIMEOUT*1000) {
                    throw "UART read timed out while waiting for newline";
                }
            }
        }
        if(_buffer.len() > 0) { // read a line with something on it
            local localBuf = _buffer;
            _buffer = "";
            _uartReadTimeoutStart = null;
            return localBuf;
        }
        return _readLineSync(); // line was empty, try again
    }

    // uart callback method, called when data is available
    function _uartCallback() {
        if(!_initialized) {
            return;
        }
        _buffer += _uart.readstring();
        local packets = _packetize_buffer();
        for (local i = 0; i < packets.len(); i++) {
            _parse(packets[i]);
        }
    }

    // parse the uart buffer into an array of packets and remove those packets from the buffer
    function _packetize_buffer() {
        local index;
        local packets = [];
        while((index = _buffer.find(_END_OF_PACKET)) != null) { // find each end of packet sequence
            local packet = _buffer.slice(0, index);
            packets.push(packet);
            _buffer = _buffer.slice(packet.len() + 3, _buffer.len());
        }
        // after packetizing buffer check if it is too long
        if(_buffer.len() > _UART_MAX_BUFFER_LENGTH) {
            _error("UART buffer exceeded max length");
            _buffer = "" // clear buffer
        }
        return packets;
    }

    // call the callback for a received packet then move on or report an error if one is not registered
    function _parse(packet) {
        if(_activeCommand != null && "callback" in _activeCommand && _activeCommand.callback != null) { // make sure there is something to call
            _activeCommand.callback({"msg" : packet}); // execute the callback
            // execute next command
            _clearActiveCommand();
            _executeNextInQueue();
        } else {
            _error("No callback registered for response '" + _buffer + "'"); // got a response with no active command
        }
    }

    // command timeout handler 
    function _handleTimeout() {
        if(_activeCommand != null && "callback" in _activeCommand && _activeCommand.callback != null) {
            _activeCommand.callback({"err": "command '" + _activeCommand.command + "' timed out"}); // callback with error
        }
        _uart.write(_END_OF_TRANSMISSION); // send EOT char to kill command
        // execute next command
        _clearActiveCommand();
        _executeNextInQueue();
    }

    // call error callback if one is registered
    function _error(errorMessage) {
        if(_errorCallback != null) {
            _errorCallback(errorMessage);
        }
    }
}

// Provides a high level interface for accessing vehicle data over OBD-II
class VehicleInterface extends STN1110 {
   
    ENGINE_RPM = 0x010C;
    VEHICLE_SPEED = 0x010D;
    THROTTLE_POSITION = 0x0111;
    COOLANT_TEMPERATURE = 0x0105;
    FUEL_PRESSURE = 0x010A;
    INTAKE_AIR_TEMPERATURE = 0x010F;
    ENGINE_RUNTIME = 0x011F;
        
    _transforms = {};
    _callbacks = null;

    function constructor(uart) {
        _callbacks = {};
        _transforms[ENGINE_RPM] <- function(data) {
            return ((data[0]*256)+data[1])/4;
        };
        _transforms[VEHICLE_SPEED] <- function(data) {
            return data[0];
        };
        _transforms[THROTTLE_POSITION] <- function(data) {
            return data[0]*100/255;
        };
        _transforms[COOLANT_TEMPERATURE] <- function(data) {
            return data[0]-40;
        };
        _transforms[FUEL_PRESSURE] <- function(data) {
            return data[0]*3;
        };
        _transforms[INTAKE_AIR_TEMPERATURE] <- function(data) {
            return data[0]-40;
        };
        _transforms[ENGINE_RUNTIME] <- function(data) {
            return (data[0]*256)+data[1];
        };
        base.constructor(uart);
    }

    // reads a PID once and executes callback with the resulting data
    function read(pid, callback) {
        _read(pid, (function(result) {
            _callback(_applyTransform(pid, result));
        }).bindenv(this));
    }

    // reads a PID every 'period' seconds calling 'callback' with the resulting data
    function subscribe(pid, callback, period) {
        _callbacks[pid] <- callback;
        _schedule(pid, period);
    }

    // unsubscribes the callback, if any, for PID 'pid'
    function unsubcribe(pid) {
        if(pid in _callbacks) {
            delete _callbacks[pid];
        }
    }

    // requests a PID and interprets the result
    function _read(pid, callback) {
        if(pid > 0xFFFF) { // sanity check
            callback({"err": "Invalid PID '" + pid + "'"});
        }
        execute(format("%04X", pid), 1, (function(result) { // format command back to hex string and execute
            if("err" in result) {
                callback(result);
                return;
            }
            local str_bytes = split(result["msg"], " ");
            local bytes = [];
            // convert response string back into bytes
            for(local i = 0; i < str_bytes.len(); i++) {
                bytes.append(this._hexToInt(str_bytes[i]));
            }
            // check that the first two bytes match what we sent (mode + 0x40 and PID code)
            if(((bytes[0] - _PID_REPLY_MODE_OFFSET) != ((pid & 0xFF00) >> 8)) || (bytes[1] != (pid & 0x00FF))) {
              callback({"err": "Response does not match requested PID"});
              return;
            }
            callback({"msg": bytes.slice(2, bytes.len())}); // skip the first two bytes which don't contain any response data
        }).bindenv(this));
    }

    // schedules a PID to be checked every 'period' seconds as long as a callback is registered in the _callbacks table
    function _schedule(pid, period) {
        if(pid in _callbacks) { // check
            _read(pid, (function(result) {
                if(pid in _callbacks) { // check again because async
                    _callbacks[pid](_applyTransform(pid, result)); // apply transform on the response data and execute callback
                }
            }).bindenv(this));
            imp.wakeup(period, (function() { _schedule(pid, period) }).bindenv(this)); // do it again
        }
    }

    // converts the response byte(s) to a value in the PIDs associates units, if hte response is valid and there is a transform for that PID
    function _applyTransform(pid, result) {
        if(!("err" in result) && pid in _transforms) {
            return { "msg": _transforms[pid](result["msg"]) };
        }
        return result;
    }

    // converts a hex string to an integer
    function _hexToInt(hex) {
        local result = 0;
        local shift = hex.len() * 4;
        for(local d=0; d<hex.len(); d++) {
            local digit;
            if(hex[d] >= 0x61) {
                digit = hex[d] - 0x57;
            } else if(hex[d] >= 0x41) {
                digit = hex[d] - 0x37;
            } else {
                digit = hex[d] - 0x30;
            }
            shift -= 4;
            result += digit << shift;
        }
        return result;
    }
}
