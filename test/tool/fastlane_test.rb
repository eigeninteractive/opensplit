# Exercise the real lane and Fastlane option validation with only the network
# action replaced. All inputs live in a disposable project, never the checkout.
require "tmpdir"
require "fileutils"
require "fastlane"

Fastlane::Actions.load_default_actions
uploads = []
Fastlane::Actions::UploadToPlayStoreAction.define_singleton_method(:run) do |options|
  uploads << options
end

def assert(condition, message)
  raise message unless condition
end

repository = File.expand_path("../..", __dir__)
original_environment = ENV.to_h
temporary = Dir.mktmpdir("opensplit-fastlane-")
begin
  FileUtils.mkdir_p(File.join(temporary, "fastlane"))
  %w[Fastfile Appfile].each do |name|
    FileUtils.cp(File.join(repository, "fastlane", name), File.join(temporary, "fastlane", name))
  end
  bundle = File.join(temporary, "build/app/outputs/bundle/release/app-release.aab")
  FileUtils.mkdir_p(File.dirname(bundle))
  File.write(bundle, "test bundle")
  credentials = File.join(temporary, "credentials.json")
  File.write(credentials, "{}")
  metadata = File.join(temporary, "metadata")
  files = %w[
    en-US/changelogs/default.txt
    en-US/images/icon.png
    en-US/images/featureGraphic.jpg
  ] + (1..5).map { |number| "en-US/images/phoneScreenshots/#{number}.png" }
  files.each do |path|
    target = File.join(metadata, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "test metadata")
  end
  ENV["GOOGLE_APPLICATION_CREDENTIALS"] = credentials
  ENV["PLAY_METADATA_DIR"] = metadata
  ENV["PLAY_TRACK"] = "alpha"
  ENV["PLAY_RELEASE_STATUS"] = "completed"
  ENV["PLAY_UPDATE_PRIORITY"] = "0"

  Dir.chdir(temporary) do
    fastfile = Fastlane::FastFile.new("fastlane/Fastfile")
    fastfile.runner.execute(:closed, :android)
    assert(uploads.size == 1, "Expected one captured upload")
    options = uploads.last
    assert(options[:metadata_path] == metadata, "Metadata path changed with Fastlane's working directory")
    assert(options[:track] == "alpha", "Release should go to closed testing")
    assert(options[:skip_upload_metadata], "Listing text should be preserved")
    %i[skip_upload_changelogs skip_upload_images skip_upload_screenshots].each do |key|
      assert(options[key] == false, "#{key} must be disabled")
    end
    assert(options[:sync_image_upload], "Unchanged artwork should be skipped")
    assert(options[:rescue_changes_not_sent_for_review] == false, "Review failures must remain visible")

    File.delete(File.join(metadata, "en-US/images/phoneScreenshots/5.png"))
    begin
      fastfile.runner.execute(:closed, :android)
      raise "Missing artwork should refuse the upload"
    rescue FastlaneCore::Interface::FastlaneError => error
      assert(error.message.include?("PLAY_METADATA_DIR"), "Expected an actionable artwork error")
    end
    assert(uploads.size == 1, "Incomplete artwork reached the upload action")
  end
  puts "Fastlane artwork upload configuration passed."
ensure
  ENV.replace(original_environment)
  FileUtils.remove_entry(temporary)
  assert(!File.exist?(temporary), "Temporary Fastlane project was not removed")
end
