import string

class GrafanaPusher
    var endpoint, auth_header
    var device_name
    var push_interval

    def init()
        # --- CONFIGURATION ---
        self.endpoint = "https://prometheus-prod-24-prod-eu-west-2.grafana.net"
        self.push_interval = 60000  # Telemetry push interval in milliseconds
        
        var username = "endpoint_username"
        var api_key = "access_policy_token"
        var raw_auth = bytes().fromstring(username + ":" + api_key)
        
        self.auth_header = "Basic " + raw_auth.tob64()
        self.device_name = tasmota.cmd("DeviceName")["DeviceName"]
        
        tasmota.log("GrafanaPusher initialized (Timer Mode).", 2)
        tasmota.set_timer(2000, def ()
            self.do_post()
            self.schedule_next()
        end)
    end

    def schedule_next()
        tasmota.set_timer(self.push_interval, def () 
            self.do_post()
            self.schedule_next()
        end)
    end

    def do_post()
        try
            # Read sensor data directly from Tasmota internal state instead of relying on broken rule hooks
            var status_data = tasmota.cmd("Status 8")
            if !status_data.contains("StatusSNS") || !status_data["StatusSNS"].contains("ENERGY")
                return
            end
            
            var energy = status_data["StatusSNS"]["ENERGY"]
            
            # Construct InfluxDB Line Protocol string safely
            var payload = string.format(
                "tasmota_power,device=%s voltage=%s,current=%s,power=%s,apparent_power=%s,reactive_power=%s,factor=%s,total=%s",
                str(self.device_name),
                str(energy["Voltage"]),
                str(energy["Current"]),
                str(energy["Power"]),
                str(energy["ApparentPower"]),
                str(energy["ReactivePower"]),
                str(energy["Factor"]),
                str(energy["Total"])
            )
            
            tasmota.log("Pushing to Grafana: " + payload, 2)
            
            # Execute HTTP POST
            var cl = webclient()
            cl.begin(self.endpoint + "/api/v1/push/influx/write")
            cl.add_header("Authorization", self.auth_header)
            cl.add_header("Content-Type", "text/plain")
            
            var res = cl.POST(payload)
            cl.close()
            
            if res != 204
                tasmota.log("Grafana HTTP Error: " + str(res), 2)
            end
            
        except .. as e, m
            tasmota.log("Grafana Exception: " + str(e) + " " + str(m), 2)
        end
    end
end

# Start the service
grafana_pusher = GrafanaPusher()
