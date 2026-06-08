class GCR::Request
  def self.from_proto(route, proto_req, *_)
    body = deep_sanitize(JSON.parse(proto_req.to_json(emit_defaults: true)))

    new(
      "route" => route,
      "class_name" => proto_req.class.name,
      "body"       => JSON.dump(body),
    )
  end

  def self.deep_sanitize(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), h|
        h[k] = GCR.filtered_parameters.key?(k) ? GCR.filtered_parameters[k] : deep_sanitize(v)
      end
    when Array
      value.map { |v| deep_sanitize(v) }
    else
      value
    end
  end
  private_class_method :deep_sanitize

  def self.from_hash(hash_req)
    new(
      "route" => hash_req["route"],
      "class_name" => hash_req["class_name"],
      "body"       => hash_req["body"],
    )
  end

  attr_reader :route, :class_name, :body

  def initialize(opts)
    @route = opts["route"]
    @class_name = opts["class_name"]
    @body = opts["body"]
  end

  def parsed_body
    @parsed_body ||= JSON.parse(body)
  end

  def to_json(*_)
    JSON.dump("route" => route, "class_name" => class_name, "body" => body)
  end

  def to_h
    {"route" => route, "class_name" => class_name, "body" => body}
  end

  def to_proto
    [route, Object.const_get(class_name).decode_json(body)]
  end

  def ==(other)
    return false unless route == other.route
    return false unless class_name == other.class_name

    parsed_body.keys.all? do |k|
      next true if GCR.ignored_fields.include?(k)
      parsed_body[k] == other.parsed_body[k]
    end
  end
end
