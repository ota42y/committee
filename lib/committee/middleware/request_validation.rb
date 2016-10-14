module Committee::Middleware
  class RequestValidation < Base
    def initialize(app, options={})
      super
      @allow_form_params   = options.fetch(:allow_form_params, true)
      @allow_query_params  = options.fetch(:allow_query_params, true)
      @check_content_type  = options.fetch(:check_content_type, true)
      @optimistic_json     = options.fetch(:optimistic_json, false)
      @coerce_query_params = options.fetch(:coerce_query_params, false)
      @strict              = options[:strict]

      # deprecated
      @allow_extra = options[:allow_extra]
    end

    def handle(request)
      link = @router.find_request_link(request)

      if link && @coerce_query_params && !request.GET.nil? && !link.schema.nil?
        request.env["rack.request.query_hash"].merge!(
          Committee::QueryParamsCoercer.new(
            request.GET,
            link.schema
          ).call
        )
      end

      request.env[@params_key] = Committee::RequestUnpacker.new(
        request,
        allow_form_params:  @allow_form_params,
        allow_query_params: @allow_query_params,
        optimistic_json:    @optimistic_json
      ).call

      if link
        validator = Committee::RequestValidator.new(link, check_content_type: @check_content_type)
        validator.call(request, request.env[@params_key])

        request.env["rack.request.query_hash"].merge!(
            Committee::ParameterConverter
                .new(request.env["rack.request.query_hash"], link.schema)
                .convert!
        )

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
