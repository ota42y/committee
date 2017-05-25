require_relative "../test_helper"

describe Committee::Middleware::RequestValidation do
  include Rack::Test::Methods

  def app
    @app
  end

  it "passes through a valid request" do
    @app = new_rack_app(schema: hyper_schema)
    params = {
      "name" => "cloudnasium"
    }
    header "Content-Type", "application/json"
    post "/apps", JSON.generate(params)
    assert_equal 200, last_response.status
  end

  it "passes given a datetime and with coerce_date_times enabled on GET endpoint" do
    key_name = "update_time"
    params = {
        key_name => "2016-04-01T16:00:00.000+09:00",
        "query" => "cloudnasium"
    }

    check_parameter = lambda { |env|
      assert_equal DateTime, env['rack.request.query_hash'][key_name].class
      [200, {}, []]
    }

    @app = new_rack_app_with_lambda(check_parameter, coerce_date_times: true, schema: hyper_schema)

    header "Content-Type", "application/json"
    get "/search/apps", params
    assert_equal 200, last_response.status
  end

  it "passes given a datetime and with coerce_date_times enabled on POST endpoint" do
    key_name = "update_time"
    params = {
        key_name => "2016-04-01T16:00:00.000+09:00"
    }

    check_parameter = lambda { |env|
      assert_equal DateTime, env['committee.params'][key_name].class
      [200, {}, []]
    }

    @app = new_rack_app_with_lambda(check_parameter, coerce_date_times: true, schema: hyper_schema)

    header "Content-Type", "application/json"
    post "/apps", JSON.generate(params)
    assert_equal 200, last_response.status
  end

  it "passes given an invalid datetime string with coerce_date_times enabled" do
    @app = new_rack_app(coerce_date_times: true, schema: hyper_schema)
    params = {
        "update_time" => "invalid_datetime_format"
    }
    header "Content-Type", "application/json"
    post "/apps", JSON.generate(params)
    assert_equal 400, last_response.status
    assert_match /invalid request/i, last_response.body
  end

  it "passes with coerce_date_times enabled and without a schema for a link" do
    @app = new_rack_app(coerce_date_times: true, schema: hyper_schema)
    header "Content-Type", "application/json"
    get "/apps", JSON.generate({})
    assert_equal 200, last_response.status
  end

  it "detects an invalid request" do
    @app = new_rack_app(schema: hyper_schema)
    header "Content-Type", "application/json"
    params = {
      "name" => 1
    }
    post "/apps", JSON.generate(params)
    assert_equal 400, last_response.status
    assert_match /invalid request/i, last_response.body
  end

  it "rescues JSON errors" do
    @app = new_rack_app(schema: hyper_schema)
    header "Content-Type", "application/json"
    post "/apps", "{x:y}"
    assert_equal 400, last_response.status
    assert_match /valid json/i, last_response.body
  end

  it "takes a prefix" do
    @app = new_rack_app(prefix: "/v1", schema: hyper_schema)
    params = {
      "name" => "cloudnasium"
    }
    header "Content-Type", "application/json"
    post "/v1/apps", JSON.generate(params)
    assert_equal 200, last_response.status
  end

  it "ignores paths outside the prefix" do
    @app = new_rack_app(prefix: "/v1", schema: hyper_schema)
    header "Content-Type", "text/html"
    get "/hello"
    assert_equal 200, last_response.status
  end

  it "routes to paths not in schema" do
    @app = new_rack_app(schema: hyper_schema)
    get "/not-a-resource"
    assert_equal 200, last_response.status
  end

  it "doesn't route to paths not in schema when in strict mode" do
    @app = new_rack_app(schema: hyper_schema, strict: true)
    get "/not-a-resource"
    assert_equal 404, last_response.status
  end

  it "optionally raises an error" do
    @app = new_rack_app(raise: true, schema: hyper_schema)
    header "Content-Type", "application/json"
    assert_raises(Committee::InvalidRequest) do
      post "/apps", "{x:y}"
    end
  end

  it "optionally skip content_type check" do
    @app = new_rack_app(check_content_type: false, schema: hyper_schema)
    params = {
      "name" => "cloudnasium"
    }
    header "Content-Type", "text/html"
    post "/apps", JSON.generate(params)
    assert_equal 200, last_response.status
  end

  it "optionally coerces query params" do
    @app = new_rack_app(coerce_query_params: true, schema: hyper_schema)
    header "Content-Type", "application/json"
    get "/search/apps", {"per_page" => "10", "query" => "cloudnasium"}
    assert_equal 200, last_response.status
  end

  it "still raises an error if query param coercion is not possible" do
    @app = new_rack_app(coerce_query_params: true, schema: hyper_schema)
    header "Content-Type", "application/json"
    get "/search/apps", {"per_page" => "foo", "query" => "cloudnasium"}
    assert_equal 400, last_response.status
    assert_match /invalid request/i, last_response.body
  end

  it "passes through a valid request for OpenAPI" do
    @app = new_rack_app(schema: open_api_2_schema)
    get "/api/pets?limit=3"
    assert_equal 200, last_response.status
  end

  it "detects an invalid request for OpenAPI" do
    @app = new_rack_app(schema: open_api_2_schema)
    get "/api/pets?limit=foo"
    assert_equal 400, last_response.status
    assert_match /invalid request/i, last_response.body
  end

  it "passes through a valid request for OpenAPI including path parameters" do
    @app = new_rack_app(schema: open_api_2_schema)
    # not that ID is expect to be an integer
    get "/api/pets/123"
    assert_equal 200, last_response.status
  end

  it "detects an invalid request for OpenAPI including path parameters" do
    @app = new_rack_app(schema: open_api_2_schema)
    # not that ID is expect to be an integer
    get "/api/pets/not-integer"
    assert_equal 400, last_response.status
    assert_match /invalid request/i, last_response.body
  end

  private

  def new_rack_app(options = {})
    new_rack_app_with_lambda(lambda { |_|
      [200, {}, []]
    }, options)
  end


  def new_rack_app_with_lambda(check_lambda, options = {})
    Rack::Builder.new {
      use Committee::Middleware::RequestValidation, options
      run check_lambda
    }
  end
end
