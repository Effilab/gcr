require_relative "./spec_helper"

describe GCR::Request do
  describe ".from_proto" do
    let(:route) { "TestRoute" }
    let(:nested_body) do
      {
        "name" => "alice",
        "token" => "top-secret",
        "nested" => {
          "token" => "nested-secret",
          "deeper" => {
            "token" => "deep-secret",
            "safe" => "keep-me"
          }
        },
        "list" => [
          {"token" => "list-secret", "label" => "item-1"},
          {"label" => "item-2"}
        ]
      }
    end
    let(:proto_double) do
      obj = double("proto_req")
      allow(obj).to receive(:to_json).with(emit_defaults: true).and_return(JSON.dump(nested_body))
      allow(obj).to receive(:class).and_return(double(name: "HelloRequest"))
      obj
    end

    before { GCR.filter_parameters(:token) }

    subject(:req) { GCR::Request.from_proto(route, proto_double) }

    it "sanitizes top-level fields" do
      expect(JSON.parse(req.body)["token"]).to eq("[FILTERED]")
    end

    it "sanitizes fields in nested hashes" do
      body = JSON.parse(req.body)
      expect(body["nested"]["token"]).to eq("[FILTERED]")
    end

    it "sanitizes fields in deeply nested hashes" do
      body = JSON.parse(req.body)
      expect(body["nested"]["deeper"]["token"]).to eq("[FILTERED]")
    end

    it "sanitizes fields inside arrays" do
      body = JSON.parse(req.body)
      expect(body["list"][0]["token"]).to eq("[FILTERED]")
    end

    it "does not affect non-filtered fields at any depth" do
      body = JSON.parse(req.body)
      expect(body["name"]).to eq("alice")
      expect(body["nested"]["deeper"]["safe"]).to eq("keep-me")
      expect(body["list"][0]["label"]).to eq("item-1")
      expect(body["list"][1]["label"]).to eq("item-2")
    end

    it "sets route and class_name" do
      expect(req.route).to eq("TestRoute")
      expect(req.class_name).to eq("HelloRequest")
    end
  end
end

describe GCR do
  subject { described_class }

  describe "#cassette_dir" do
    it "raises if not configured" do
      subject.cassette_dir = nil

      expect {
        subject.cassette_dir
      }.to raise_exception(GCR::ConfigError)
    end

    it "returns cassette dir if configured" do
      expect(subject.cassette_dir).to eq(TMP_DIR)
    end
  end

  describe "#with_cassette" do
    it "records" do
      # Record
      subject.with_cassette("foo") do
        expect(Greetings::Client.hello("bob")).to eq("resp 0 — hello bob")
        expect(Greetings::Client.hello("sue")).to eq("resp 1 — hello sue")
        expect(Greetings::Client.hello("sue")).to eq("resp 2 — hello sue")

        # with request_id field
        expect(Greetings::Client.hello("joe", "1")).to eq("resp 3 — hello joe")
      end

      Greetings::Server.stop

      # Play
      subject.with_cassette("foo") do
        expect(Greetings::Client.hello("bob")).to eq("resp 0 — hello bob")
        expect(Greetings::Client.hello("sue")).to eq("resp 1 — hello sue")
        expect(Greetings::Client.hello("sue")).to eq("resp 2 — hello sue")
        expect {
          Greetings::Client.hello("fred")
        }.to raise_exception(GCR::NoRecording)

        # with request_id field
        expect {
          Greetings::Client.hello("joe", "2")
        }.to raise_exception(GCR::NoRecording)

        GCR.ignore(:requestId)

        expect(Greetings::Client.hello("joe", "2")).to eq("resp 3 — hello joe")
      end
    end

    it "filters configured parameters with default placeholder when recording" do
      GCR.filter_parameters(:requestId)

      subject.with_cassette("filter_default") do
        expect(Greetings::Client.hello("joe", "1")).to include("hello joe")
      end

      data = JSON.parse(File.read(File.join(TMP_DIR, "filter_default.json")))
      body = JSON.parse(data["reqs"][0][0]["body"])

      expect(body["requestId"]).to eq("[FILTERED]")
    end

    it "filters configured parameters with custom placeholder when recording" do
      GCR.filter_parameters_with(requestId: "[REQUEST_ID]")

      subject.with_cassette("filter_custom") do
        expect(Greetings::Client.hello("joe", "1")).to include("hello joe")
      end

      data = JSON.parse(File.read(File.join(TMP_DIR, "filter_custom.json")))
      body = JSON.parse(data["reqs"][0][0]["body"])

      expect(body["requestId"]).to eq("[REQUEST_ID]")
    end

    it "matches filtered fields during playback" do
      GCR.filter_parameters(:requestId)

      recorded_response = nil
      subject.with_cassette("filter_playback") do
        recorded_response = Greetings::Client.hello("joe", "1")
        expect(recorded_response).to include("hello joe")
      end

      Greetings::Server.stop

      subject.with_cassette("filter_playback") do
        expect(Greetings::Client.hello("joe", "2")).to eq(recorded_response)
      end
    end
  end
end
