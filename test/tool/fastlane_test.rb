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

def refuses_upload(fastfile, uploads, lane, message)
  before = uploads.size
  begin
    fastfile.runner.execute(lane, :android)
    raise "Expected #{lane} to refuse #{message}"
  rescue FastlaneCore::Interface::FastlaneError, ArgumentError => error
    assert(error.message.include?(message), "Unexpected error: #{error.message}")
  end
  assert(uploads.size == before, "Invalid inputs reached the upload action")
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

    # Production's track and status cannot drift through old repository vars.
    ENV["PLAY_TRACK"] = "alpha"
    ENV["PLAY_RELEASE_STATUS"] = "draft"
    ENV.delete("PLAY_UPDATE_PRIORITY")
    fastfile.runner.execute(:production, :android)
    options = uploads.last
    assert(options[:track] == "production", "Production lane must publish to production")
    assert(options[:release_status] == "completed", "Production must request full rollout")
    assert(options[:rollout].nil?, "Production must not leave a staged rollout")
    assert(options[:in_app_update_priority] == 0, "Ordinary releases must default to priority 0")
    assert(File.realpath(options[:aab]) == File.realpath(bundle), "Production must use the signed CI bundle")
    assert(options[:metadata_path] == metadata, "Production must include the prepared notes and artwork")
    assert(options[:rescue_changes_not_sent_for_review] == false, "Production review failures must remain visible")

    ENV["PLAY_UPDATE_PRIORITY"] = "4"
    fastfile.runner.execute(:production, :android)
    assert(uploads.last[:in_app_update_priority] == 4, "Explicit urgent priority must be preserved")
    ENV["PLAY_UPDATE_PRIORITY"] = "0"

    fastfile.runner.execute(:internal, :android)
    assert(uploads.last[:track] == "internal", "Internal lane must remain available")
    assert(uploads.last[:release_status] == "draft", "Testing can still prepare drafts")
    ENV["PLAY_TRACK"] = "production"
    refuses_upload(fastfile, uploads, :closed, "PLAY_TRACK")
    ENV["PLAY_TRACK"] = "alpha"
    ENV["PLAY_RELEASE_STATUS"] = "inProgress"
    refuses_upload(fastfile, uploads, :closed, "PLAY_RELEASE_STATUS")
    ENV["PLAY_RELEASE_STATUS"] = "completed"
    [-1, 6, "urgent"].each do |priority|
      ENV["PLAY_UPDATE_PRIORITY"] = priority.to_s
      refuses_upload(fastfile, uploads, :production, "PLAY_UPDATE_PRIORITY")
    end
    ENV["PLAY_UPDATE_PRIORITY"] = "0"

    File.delete(File.join(metadata, "en-US/images/phoneScreenshots/5.png"))
    refuses_upload(fastfile, uploads, :production, "PLAY_METADATA_DIR")
    File.write(File.join(metadata, "en-US/images/phoneScreenshots/5.png"), "test metadata")
    File.delete(bundle)
    refuses_upload(fastfile, uploads, :production, "signed release AAB")
    File.write(bundle, "test bundle")
    File.delete(credentials)
    refuses_upload(fastfile, uploads, :production, "credentials file")
  end
  puts "Fastlane production and testing upload configuration passed."
ensure
  ENV.replace(original_environment)
  FileUtils.remove_entry(temporary)
  assert(!File.exist?(temporary), "Temporary Fastlane project was not removed")
end
