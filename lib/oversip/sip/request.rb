module OverSIP::SIP

  class Request < Message

    SECURE_TRANSPORTS = { :tls=>true, :wss=>true }

    attr_accessor :server_transaction
    attr_reader :ruri
    attr_reader :new_max_forwards
    attr_accessor :antiloop_id
    attr_accessor :route_outbound_flow_token

    attr_writer :outgoing_outbound_requested, :incoming_outbound_requested
    attr_accessor :proxied   # If true it means that this request has been already proxied.

    # Used for internal purposes when doing proxy and adding the first Record-Route
    # or Path.
    attr_accessor :in_rr


    def log_id
      @log_id ||= "SIP Request #{@via_branch_id}"
    end

    def request?      ; true         end
    def response?     ; false        end

    def initial?      ; ! @to_tag    end
    def in_dialog?    ; @to_tag      end

    def secure?
      SECURE_TRANSPORTS[@transport] || false
    end


    def reply status_code, reason_phrase=nil, extra_headers=[], body=nil
      return false  unless @server_transaction.receive_response(status_code)  if @server_transaction

      reason_phrase ||= REASON_PHARSE[status_code] || REASON_PHARSE_NOT_SET

      if status_code > 100
        @internal_to_tag ||= @to_tag || ( @server_transaction ? SecureRandom.hex(6) : OverSIP::SIP::Tags.totag_for_sl_reply )
      end

      response = "SIP/2.0 #{status_code} #{reason_phrase}\r\n"

      @hdr_via.each do |hdr|
        response << "Via: " << hdr << "\r\n"
      end

      response << "From: " << @hdr_from << "\r\n"

      response << "To: " << @hdr_to
      response << ";tag=#{@internal_to_tag}"  if @internal_to_tag
      response << "\r\n"

      response << "Call-ID: " << @call_id << "\r\n"
      response << "CSeq: " << @cseq.to_s << " " << @sip_method.to_s << "\r\n"
      response << "Content-Length: #{body ? body.bytesize : "0"}\r\n"

      extra_headers.each do |header|
        response << header.to_s << "\r\n"
      end  if extra_headers

      response << HDR_SERVER << "\r\n"
      response << "\r\n"

      response << body  if body

      @server_transaction.last_response = response  if @server_transaction

      log_system_debug "replying #{status_code} \"#{reason_phrase}\""  if $oversip_debug

      send_response(response)
      true
    end


    def reply_full response
      return false  unless @server_transaction.receive_response(response.status_code)  if @server_transaction

      # Ensure the response has Content-Length. Add it otherwise.
      if response.body
        response.headers["Content-Length"] = [ response.body.bytesize.to_s ]
      else
        response.headers["Content-Length"] = HDR_ARRAY_CONTENT_LENGTH_0
      end

      response_leg_a = response.to_s
      @server_transaction.last_response = response_leg_a  if @server_transaction

      log_system_debug "forwarding response #{response.status_code} \"#{response.reason_phrase}\""  if $oversip_debug

      send_response(response_leg_a)
      true
    end


    def send_response(response)
      unless (case @transport
        when :udp
          @connection.send_sip_msg response, @source_ip, @via_rport || @via_sent_by_port || 5060
        else
          @connection.send_sip_msg response
        end
      )
        log_system_notice "error sending the SIP response"
      end
    end


    def to_s
      msg = "#{@sip_method.to_s} #{self.ruri.uri} SIP/2.0\r\n"

      @headers.each do |key, values|
        values.each do |value|
          msg << key << ": #{value}\r\n"
        end
      end

      msg << CRLF
      msg << @body  if @body
      msg
    end

  end  # class Request

end