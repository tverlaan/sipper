require 'util/sipper_util'
require 'digest/md5'
require 'base64'
require 'sipper_configurator'
require 'sip_headers/header'


# Digest authorizer is a stateful entity that maintains the state from previous challenges and
# calculates the digest according to RFC. 
module SipperUtil
  class DigestAuthorizer
    
    attr_writer :salt
    
    def initialize(salt=nil)
      @same_challenge = true
      @salt = salt || SipperConfigurator[:DigestSalt] || "sipper_rocks"
      @nonce_count_table = {}
    end
    
    # Generated by UAC to respond to the challenge
    def create_authorization_header(c, proxy, u, p, lsr)
      @same_challenge = (@c.nonce == c.nonce)  if @c
      @c = c
      @u = u
      @p = p 
      @lsr = lsr
      @cnonce = create_nonce if @c.qop
      if @nonce_count_table[@c.nonce]
        @nonce_count_table[@c.nonce] += 1
      else  
        @nonce_count_table[@c.nonce] = 1
      end
      if proxy
        atn_hdr = SipHeaders::ProxyAuthorization.new
      else
        atn_hdr = SipHeaders::Authorization.new
      end
      atn_hdr.scheme = @c.scheme 
      atn_hdr.username = SipperUtil.quote_str @u 
      atn_hdr.realm = @c.realm 
      atn_hdr.nonce = @c.nonce 
      atn_hdr.uri = SipperUtil.quote_str @lsr.uri.to_s
      atn_hdr.nc = nonce_count()
      atn_hdr.opaque = @c.opaque 
      atn_hdr.algorithm = @c.algorithm
      atn_hdr.qop = @c.qop 
      atn_hdr.cnonce = SipperUtil.quote_str @cnonce if @cnonce
      atn_hdr.response = SipperUtil.quote_str digest_response()
      return atn_hdr
    end
    
    
    # generated by UAS or Proxy to create a challenge
    # attr_accessor :scheme, :realm, :domain, :nonce, :opaque, :stale, :algorithm,
    # :qop
    def create_authentication_header(realm, domain, add_opaque=false, stale=false, proxy=false, qop=true)
      if proxy
        auth_hdr = SipHeaders::ProxyAuthenticate.new
      else
        auth_hdr = SipHeaders::WwwAuthenticate.new
      end
      auth_hdr.scheme = "Digest"
      auth_hdr.realm = SipperUtil.quote_str realm
      auth_hdr.domain = SipperUtil.quote_str domain if domain
      auth_hdr.nonce = SipperUtil.quote_str create_nonce
      auth_hdr.opaque = SipperUtil.quote_str create_nonce if add_opaque
      auth_hdr.qop = SipperUtil.quote_str "auth" if qop
      if stale
        auth_hdr.stale = "TRUE"
      else
        auth_hdr.stale = "FALSE"
      end
      auth_hdr.algorithm = "MD5"
      @c = auth_hdr
      return auth_hdr
    end
    
    # Used by UAS to authenticate after getting the authenticated request
    def do_authentication(req, u, p)
      return false unless @c
      if req[:authorization]
        atn_hdr = req.authorization
      elsif req[:proxy_authorization]
        atn_hdr = req.proxy_authorization
      else
        return false
      end  
      @same_challenge =  true
      @u = u
      @p = p
      @lsr = req
      @cnonce = SipperUtil.unquote_str atn_hdr.cnonce if atn_hdr.cnonce 
      @nonce_count_table[@c.nonce] = (SipperUtil.unquote_str(atn_hdr.nc)).to_i
      created_response = digest_response()
      received_response = SipperUtil.unquote_str atn_hdr.response
      return (created_response == received_response)
    end
    
    private
    
    def concat(*args) 
      args.join ':' 
    end
    
    # Calculate H() as specified, this is just a simple hash.
    # RFC 2617 : For the "MD5" and "MD5-sess" algorithms
    # H(data) = MD5(data)
    def h(data)
      Digest::MD5.hexdigest data 
    end
    
    
    # RFC 2617 :  KD(secret, data) = H(concat(secret, ":", data)
    def kd(secret, data)
      h concat(secret, data)
    end
    
    
    def user_string
      concat(@u, SipperUtil.unquote_str(@c.realm), @p)
    end
    
    
    # A1
    # RFC 2617 3.2.2.2 A1
    
    #   If the "algorithm" directive's value is "MD5" or is unspecified, then
    #   A1 is:
    #
    #      A1       = unq(username-value) ":" unq(realm-value) ":" passwd
    #   where
    #      passwd   = < user's password >
    #
    #   If the "algorithm" directive's value is "MD5-sess", then A1 is
    #   calculated only once - on the first request by the client following
    #   receipt of a WWW-Authenticate challenge from the server.  It uses the
    #   server nonce from that challenge, and the first client nonce value to
    #   construct A1 as follows:
    #
    #      A1       = H( unq(username-value) ":" unq(realm-value)
    #                     ":" passwd )
    #                     ":" unq(nonce-value) ":" unq(cnonce-value)
    #
    #   This creates a 'session key' for the authentication of subsequent
    #   requests and responses which is different for each "authentication
    #   session", thus limiting the amount of material hashed with any one
    #   key. 
    def a1
      if @c.algorithm == 'MD5-sess'
        if @same_challenge
          if @cnonce
            @a1_sess = concat(h(user_string), SipperUtil.unquote_str(@c.nonce), SipperUtil.unquote_str(@cnonce))  unless  @a1_sess
          else
            @a1_sess = concat(h(user_string), SipperUtil.unquote_str(@c.nonce))  unless  @a1_sess
          end
          @a1_sess
        else
          if @cnonce
            @a1_sess = concat(h(user_string), SipperUtil.unquote_str(@c.nonce), SipperUtil.unquote_str(@cnonce))
          else
            @a1_sess = concat(h(user_string), SipperUtil.unquote_str(@c.nonce))
          end
        end
      else
        user_string
      end
      
    end
    
    # 3.2.2.3 A2
    
    # If the "qop" directive's value is "auth" or is unspecified, then A2
    # is:
    #
    # A2       = Method ":" digest-uri-value
    #  If the "qop" value is "auth-int", then A2 is:
    #
    # A2       = Method ":" digest-uri-value ":" H(entity-body)    
    #
    # From 3261
    # As a clarification to the calculation of the A2 value for
    # message integrity assurance in the Digest authentication
    # scheme, implementers should assume, when the entity-body is
    # empty (that is, when SIP messages have no body) that the hash
    # of the entity-body resolves to the MD5 hash of an empty
    # string, or:
    # H(entity-body) = MD5("") =
    # "d41d8cd98f00b204e9800998ecf8427e"
    def a2
      if @c.qop && @c.qop == 'auth-int'
        concat(@lsr.method, @lsr.uri.to_s, h(b=@lsr.body ? b : ""))
      else
        concat(@lsr.method, @lsr.uri.to_s)
      end
    end
    
    
    
    # If the "qop" value is "auth" or "auth-int":
    # request-digest = <"> < KD ( H(A1), unq(nonce-value)
    # ":" nc-value
    # ":" unq(cnonce-value)
    # ":" unq(qop-value)
    # ":" H(A2)
    # ) <">
    # If the "qop" directive is not present (this construction is for
    # compatibility with RFC 2069):
    # request-digest =
    # <"> < KD ( H(A1), unq(nonce-value) ":" H(A2) ) >
    # <">
    def digest_response
      if @c.qop.nil?
        kd(h(a1), concat(SipperUtil.unquote_str(@c.nonce), h(a2)))
      else 
        kd(h(a1), concat(SipperUtil.unquote_str(@c.nonce), 
                         nonce_count(), 
                         SipperUtil.unquote_str(@cnonce), SipperUtil.unquote_str(@c.qop), h(a2)))
      end
    end
    
    
    def create_nonce
      now = Time.now
      time = now.strftime("%Y-%m-%d %H:%M:%S").to_s + ':' + now.usec.to_s
      Base64.encode64(
                      concat(time, h(concat(time, @salt)))
      ).gsub("\n", '')[0..-3]
    end
    
    def create_opaque
      s = []; 16.times { s << rand(127).chr }
      h s.join
    end
    

    
    def nonce_count
      (@nonce_count_table[@c.nonce]).to_s(16).rjust 8, '0'
    end
    
    

  end  # class
  
end  # module