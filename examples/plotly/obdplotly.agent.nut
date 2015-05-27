#require "Plotly.class.nut:1.0.0"

const PLOTLY_USER = "your plotly user name"
const PLOTLY_API_KEY = "your plotly api key"


local traces = ["rpm", "speed", "throttle", "runtime", "coolant_temp", "intake_temp", "fuel_pressure"];
plot1 <- Plotly("jreimers", "8zwalnxupk", "obd-test-5", true, traces, function(response, plot) {
    // output plot url
    server.log("plot url: " + plot.getUrl());
    // set plot params
    plot.setTitle("OBD-II Data");
    plot.setAxisTitles("time", "data");
    // register function to handle log messages from the device
    device.on("log", function(log) {
        local timestamp = plot.getPlotlyTimestamp();
        local plot_data = []
        foreach(k,v in log) {
            server.log(k + ": " + v) // output data
            plot_data.append({ // append to plot
                "name" : k,
                "x" : [timestamp],
                "y" : [v]
            })
        }
        plot.post(plot_data)
    })
});
