module Committee::Middleware
  class RequestValidation < Base
    def initialize(app, options={})
      super

      @allow_form_params   = options.fetch(:allow_form_params, true)
      @allow_query_params  = options.fetch(:allow_query_params, true)
      @check_content_type  = options.fetch(:check_content_type, true)
      @optimistic_json     = options.fetch(:optimistic_json, false)
      @strict              = options[:strict]

      @coerce_path_params = options.fetch(:coerce_path_params,
        @schema.driver.default_path_params)
      @coerce_query_params = options.fetch(:coerce_query_params,
        @schema.driver.default_query_params)

      # deprecated
      @allow_extra = options[:allow_extra]
    end

    def handle(request)
      link, param_matches = @router.find_request_link(request)
      path_params = {}

      if link
        # Attempts to coerce parameters that appear in a link's URL to Ruby
        # types that can be validated with a schema.
        if @coerce_path_params
          path_params = param_matches.merge(
            Committee::StringParamsCoercer.new(
              param_matches,
              link.schema
            ).call
          )
        end

        # Attempts to coerce parameters that appear in a query string to Ruby
        # types that can be validated with a schema.
        if @coerce_query_params && !request.GET.nil? && !link.schema.nil?
          request.env["rack.request.query_hash"].merge!(
            Committee::StringParamsCoercer.new(
              request.GET,
              link.schema
            ).call
          )
        end
      end

      request.env[@params_key] = Committee::RequestUnpacker.new(
        request,
        allow_form_params:  @allow_form_params,
        allow_query_params: @allow_query_params,
        optimistic_json:    @optimistic_json
      ).call

      request.env[@params_key].merge!(path_params)

      if link
        validator = Committee::RequestValidator.new(link, check_content_type: @check_content_type)
        validator.call(request, request.env[@params_key])
        @app.call(request.env)
      elsif @strict
        raise Committee::NotFound
      else
        @app.call(request.env)
      end
    rescue Committee::BadRequest, Committee::InvalidRequest
      raise if @raise
      @error_class.new(400, :bad_request, $!.message).render
    rescue Committee::NotFound
      raise if @raise
      @error_class.new(
        404,
        :not_found,
        "That request method and path combination isn't defined."
      ).render
    rescue JSON::ParserError
      raise Committee::InvalidRequest if @raise
      @error_class.new(400, :bad_request, "Request body wasn't valid JSON.").render
    end
  end
end
