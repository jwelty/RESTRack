module RESTRack
  class ResourceRequest
    attr_reader :request, :request_id, :input, :get_query_string, :get_query_hash
    attr_accessor :content_type, :path_stack, :format, :resource_name, :action, :id

# TODO: Load from app constants.yml the whitelist and/or (?just 'or'?) blacklist of root level resources. All resources are accessible from the root level if no config options are present.

    def initialize(opts)
      # Initialize the ResourceRequest by assigning a request_id and determining the path, format, and controller of the resource.
      # Accepting options just to allow us to override request_id for testing.
      @request = opts[:request]
      @request_id = opts[:request_id] || get_request_id

      # Gather input params
      input_str = @request.body.read
      @get_query_hash = @request.GET
      @get_query_string = @request.query_string

      RESTRack::WebService.log.debug "Reading POST Input (Request ID: #{@request_id})"
      # Pull input data from POST body if present, otherwise from GET query
      # TODO: Does this make sense? Perhaps support XML as a standard input and also binary types!
      # Can this inspect the content-type of the input, and load @input intelligently?
      @input = input_str.length > 0 ? JSON.parse( input_str ) : @get_query_hash

      # Write input details to logs
      RESTRack::WebService.request_log.info "Request ID: #{@request_id}\n" + ({
        'ip' => @request.ip
      }).to_json
      RESTRack::WebService.request_log.debug "JSON Data In (Request ID: #{@request_id})\n" + input_str

      # Path stack keeps track of what on the requets path is yet to be followed.
      @path_stack = @request.path_info
      # Determine the response format
      get_format
      # Parse out the controller of the resource being requested from the path.
      # @path_stack will start with a forward slash here, so the first item returned will be an empty string.
      ( empty_str, @resource_name, @id, @action, @path_stack ) = @path_stack.split('/', 5)
      # Verify that initial resource in the request chain is accessible at the root.
      raise HTTP403Forbidden unless RESTRack::CONFIG[:ROOT_RESOURCE_ACCEPT].blank? or RESTRack::CONFIG[:ROOT_RESOURCE_ACCEPT].include?(@resource_name)
      raise HTTP403Forbidden if not RESTRack::CONFIG[:ROOT_RESOURCE_DENY].blank? and RESTRack::CONFIG[:ROOT_RESOURCE_DENY].include?(@resource_name)
      # Set and return the controller
      @resource_name = RESTRack::Support.camelize( @resource_name )
    end

    def locate
      # Locate the correct controller of resource based on the request.
      # The resource requested must be a member of RESTRack application or a 404 error will be thrown by RESTRack::WebService.
      RESTRack::WebService.log.debug "Locating Resource (Request ID: #{@request_id})"
      @resource = instantiate_controller
    end

    def call
      # Pass along the `call` method to the typed resource object, this must occur after a call to locate.
      RESTRack::WebService.log.debug "Processing Request (Request ID: #{@request_id})"
      @resource.call
    end

    def output
      # Send out the typed resource's output, this must occur after a call to run.
      RESTRack::WebService.log.debug "Retrieving Output (Request ID: #{@request_id})"
      @resource.output
    end

    private
    def get_request_id
      # TODO: Should this / can this be a more unique identifier?
      t = Time.now
      return t.strftime('%s') + t.usec.to_s
    end

    def get_format
      # Determine the format for the response.
      # Remove the extension from the URL if present, and use that to determine format.
      extension = ''
      unless @path_stack.nil?
        @path_stack = @path_stack.sub(/\.([^.]*)$/) do |s|
          extension = $1.downcase
          '' # Return an empty string as the substitution so that the extension is removed from `path_stack`
        end
      end
      if not get_query_hash.has_key?(format)
        # Get the format type requested, or use the default if none or unsupported was provided.
        @format = RESTRack::CONFIG[:DEFAULT_FORMAT]
        @format = :JSON if extension == 'json'
        @format = :XML if extension == 'xml'
      else
        @format = get_query_hash[format].upcase.to_sym
      end
    end

    def instantiate_controller
      # Called from the locate method, this method dynamically finds the class based on the URI and instantiates an object of that class via the __init method on RESTRack::ResourceController.
      begin
        return Kernel.const_get( RESTRack::CONFIG[:SERVICE_NAME].to_sym ).const_get( "#{@resource_name}Controller".to_sym ).__init(self)
      rescue
        raise HTTP404ResourceNotFound, "The resource #{RESTRack::CONFIG[:SERVICE_NAME]}::#{@resource_name}Controller could not be instantiated."
      end
    end

  end # class ResourceRequest
end # module RESTRack
