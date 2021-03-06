
# Media Event includes both the Events generated by the media
# client as well as the responses to the requests sent.
#
module Media

  class SipperMediaEvent
    attr_accessor :session
    def initialize(session)
      @session = session  
    end
    
    def short_to_s
      self.to_s
    end
    
  end
  
  class SmReply < SipperMediaEvent
    attr_reader :cmd, :media_id, :reason, :recv_ip, :recv_port, :result, :otherparams
    def initialize(session, cmd, result, mediaid=nil, reason=nil, recvip=nil, recvport=nil, otherparam=nil)
      super(session)
      @cmd = cmd
      @result = result
      @media_id = mediaid
      @reason = reason
      @recv_ip = recvip
      @recv_port = recvport
      @otherparams = otherparam
    end
  end
  
  class SmEvent < SipperMediaEvent
    attr_reader :codec, :event, :dtmf, :media_id
    def initialize(session, mediaid, codec, event, dtmf=nil)
      super(session)
      @codec = codec
      @event = event
      @dtmf = dtmf
      @media_id = mediaid
    end
  end
end
