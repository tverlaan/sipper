#   PUA                    Server                    Watcher
#     |                         |   (1) SUBSCRIBE        |
#     |                         |     Event:presence       |
#     |                         |    <------------------      |
#     |                         |   (2) 200 OK               |
#     |                         |      ------------------>    |
#     |                         |   (3) NOTIFY             |
#     |                         |     ------------------>     |
#     |                         |   (4) 200 OK               |
#     |                         |     <------------------     |
#     |(5) REGISTER     |                                  |
#     |------------------>  |                                 |
#     |(6) 200 OK          |                                 |
#     |<------------------ |                                  |
#     |                         |     (7) NOTIFY           |
#     |                         |     ------------------>     |
#     |                         |     (8) 200 OK             |
#     |                         |     <------------------    |

require 'driven_sip_test_case'

class TestPresenceEvent < DrivenSipTestCase

  def setup
    super
    
    str = <<-EOF
    
    require 'sip_test_driver_controller'
    
    module TestPresenceEvent_SipInline
    
      class PresenceUserController < SIP::SipTestDriverController
     
      transaction_usage :use_transactions=>false
        def start
          u = create_udp_session(SipperConfigurator[:LocalSipperIP], SipperConfigurator[:LocalTestPort])
          r = u.create_register_request("sip:sipper.com", "sip:joe@example.com", ["sip:bob@192.168.1.2","sip:bob@sipper.com"])
          u.send(r)
        end
        
        def on_success_res(session)
            session.invalidate(true)
        end
                
      end
    
        
      class PresenceServController < SIP::SipTestDriverController
      
        transaction_usage :use_transactions=>false
        session_timer 1500

        def on_subscribe(session)
          session[:subs_req] = session.irequest
          subscription = session.get_subscription(session.irequest)
          if subscription == nil
            subscription = session.create_subscription_from_request(session.irequest)
          else
            subscription = session.update_subscription(session.irequest)
          end
          session.respond_with(200)

          notifyReq = session.create_subsequent_request("NOTIFY")
          session.add_subscription_to_request(notifyReq, subscription)
          notifyReq.expires = "3599"
          notifyReq.content_type = "application/pidf+xml"
          notifyReq.content = session.create_pidf_doc(session.irequest.uri.to_s,nil,"No Update !!").to_s
          session.send_request(notifyReq)

          dialog_info = session.call_id + "," + session.local_tag + "," + session.remote_tag  
          dialog_store.put("watchSession", dialog_info) 
        end

        def on_register(session)
            session.respond_with(200)              
            dialog_info = dialog_store.get("watchSession")
            dialog = dialog_info.split(',')  
            watchSession = SessionManager.find_session(dialog[0], dialog[1], dialog[2])
            msg = CustomMessage.new
            watchSession.post_custom_message(msg)
            session.invalidate(true)
        end
        
        def on_custom_msg(watchSession, msg)
          notifyReq = watchSession.create_subsequent_request("NOTIFY")
          subscription = watchSession.get_subscription(watchSession[:subs_req])
          watchSession.add_subscription_to_request(notifyReq, subscription)
          notifyReq.expires = "3599"
          notifyReq.content_type = "application/pidf+xml"
          
          # contact_addr and contact_priority can be picked from registration store. 
          
          pidfdata = XmlDoc::PidfTuple.new("open", "sip:nasir@sipper.com", "0.2", "Welcome to SIPr World !!")
          notifyReq.content = watchSession.create_pidf_doc("sip:joe@example.com", pidfdata,"Registration done !!").to_s
          watchSession.send(notifyReq)  
        end
        
        def on_success_res_for_notify(session)
          if !session['2xx']
            session['2xx'] =1 
          elsif session['2xx'] ==1
            dialog_store.delete("watchSession")
            session.invalidate(true)
            session.flow_completed_for("TestPresenceEvent")  
          end
        end

        def order
          0
        end
      end
      
      class WatchController < SIP::SipTestDriverController
        transaction_usage :use_transactions=>false        
                
        def start
          r = Request.create_initial("SUBSCRIBE", "sip:joe@example.com", :p_session_record=>"msg-info")
          u = create_udp_session(SipperConfigurator[:LocalSipperIP], SipperConfigurator[:LocalTestPort])
          subscription = u.create_subscription("presence")
          u.add_subscription_to_request(r, subscription)
          r.expires = "3600"
          u.send(r)
        end
     
        def on_notify(session)
          if !session['notify']
            session.respond_with(200)
            session['notify'] = 1
          elsif session['notify'] == 1
            session.respond_with(200)
            session.invalidate(true)
          end
        end
      end
      
    end
    EOF
    define_controller_from(str)
  end
  
  
  def test_presence_event
    self.expected_flow = ["> SUBSCRIBE","< 200", "< NOTIFY", "> 200", "< NOTIFY", "> 200"]
    start_named_controller_non_blocking("TestPresenceEvent_SipInline::WatchController")
    sleep 1
    start_named_controller("TestPresenceEvent_SipInline::PresenceUserController")
    sleep 1
    verify_call_flow(:out,0)
    
    self.expected_flow = ["< SUBSCRIBE","> 200", "> NOTIFY", "< 200", "> NOTIFY", "< 200"]
    verify_call_flow(:in,0)
    
  end
  
  def teardown
    SIP::Locator[:RegistrationStore].destroy
    SIP::Locator[:DialogInfoStore].destroy
    super
  end
  
end


