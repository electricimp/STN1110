#require "Plotly.class.nut:1.0.0"

const PLOTLY_USER = "your plotly user name"
const PLOTLY_API_KEY = "your plotly api key"

// register the function to handle data messages from the device
device.on("log", function(log) {
	local timestamp = plot1.getPlotlyTimestamp();
	local plot_data = []
	foreach(k,v in log) {
		server.log(k + ": " + v) // output data
		plot_data.append({ // append to plot
			"name" : k,
            "x" : [timestamp],
            "y" : [v]
		})
	}
    plot1.post(plot_data)
})


local traces = ["rpm", "speed", "throttle", "runtime", "coolant_temp", "intake_temp", "fuel_pressure"];
plot1 <- Plotly(PLOTLY_USER, PLOTLY_API_KEY, "obd-test", true, traces);
plot1.setTitle("OBD-II Data");
plot1.setAxisTitles("time", "data");

server.log(plot1.getUrl());