require_relative "./spec_helper"

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
        expect(Greetings::Client.hello("sue")).to eq("resp 1 — hello sue")
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
