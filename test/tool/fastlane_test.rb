# Exercise the real lane and Fastlane option validation with only the network
# action replaced. All inputs live in a disposable project, never the checkout.
require "tmpdir"
require "fileutils"
require "fastlane"
require "open3"
require "yaml"

Fastlane::Actions.load_default_actions
uploads = []
Fastlane::Actions::UploadToPlayStoreAction.define_singleton_method(:run) do |options|
  uploads << options
end

def assert(condition, message)
  raise message unless condition
end

def run_command(*arguments, **options)
  output, status = Open3.capture2e(*arguments, **options)
  assert(status.success?, "#{arguments.inspect} failed: #{output}")
  output.strip
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
  ENV["PLAY_PREVIOUS_VERSION"] = "4.1.0"
  ENV["PLAY_APP_VERSION"] = "4.1.1"

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
    assert(options[:in_app_update_priority] == 0, "Patch releases must have priority 0")
    assert(File.realpath(options[:aab]) == File.realpath(bundle), "Production must use the signed CI bundle")
    assert(options[:metadata_path] == metadata, "Production must include the prepared notes and artwork")
    assert(options[:rescue_changes_not_sent_for_review] == false, "Production review failures must remain visible")

    # Production's priority comes from the version delta, not old hosted vars.
    ENV["PLAY_UPDATE_PRIORITY"] = "5"
    [
      ["4.1.0", "4.1.1", 0],
      ["4.1.0", "4.2.0", 2],
      ["4.1.0", "5.0.0", 5],
      ["4.1.0", "5.0.1", 5], # A pending major followed by a patch.
      ["4.1.0", "4.2.1", 2], # A pending minor followed by a patch.
      ["4.9.9", "4.10.0", 2],
      ["5.0.0", "5.0.1", 0],
      ["4.2.0", "4.2.1", 0]
    ].each do |previous, current, priority|
      ENV["PLAY_PREVIOUS_VERSION"] = previous
      ENV["PLAY_APP_VERSION"] = current
      fastfile.runner.execute(:production, :android)
      assert(uploads.last[:in_app_update_priority] == priority,
             "#{previous} -> #{current} must have priority #{priority}")
    end
    ["4.1.0", "4.0.9", "5.0.0-beta.1", "4.1.1+2", "4.2", ""].each do |version|
      ENV["PLAY_PREVIOUS_VERSION"] = "4.1.0"
      ENV["PLAY_APP_VERSION"] = version
      refuses_upload(fastfile, uploads, :production, "PLAY_APP_VERSION")
    end
    ENV["PLAY_APP_VERSION"] = "4.1.1"
    ENV["PLAY_PREVIOUS_VERSION"] = "invalid"
    refuses_upload(fastfile, uploads, :production, "PLAY_PREVIOUS_VERSION")
    ENV["PLAY_PREVIOUS_VERSION"] = "4.1.0"
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
      refuses_upload(fastfile, uploads, :internal, "PLAY_UPDATE_PRIORITY")
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
  # Exercise the actual workflow step with Git history and tags. Only Cider's
  # version command is stubbed; no build, upload or external remote is involved.
  workflow = YAML.load_file(File.join(repository, ".github/workflows/release.yml"))
  steps = workflow.fetch("jobs").fetch("publish").fetch("steps")
  checkout = steps.find { |step| step["uses"] == "actions/checkout@v7" }
  assert(checkout.dig("with", "fetch-depth") == 0, "Release tag lookup needs full history")
  script = steps.find { |step| step["name"] == "Number this build" }.fetch("run")
  history = File.join(temporary, "history")
  origin = File.join(temporary, "origin.git")
  bin = File.join(temporary, "bin")
  FileUtils.mkdir_p([history, bin])
  run_command("git", "init", "--quiet", "--bare", origin)
  run_command("git", "init", "--quiet", "--initial-branch=main", history)
  git = lambda do |*arguments|
    run_command("git", "-c", "user.name=Release test",
                "-c", "user.email=release@example.invalid",
                "-c", "commit.gpgsign=false", *arguments, chdir: history)
  end
  git.call("remote", "add", "origin", origin)
  commit = lambda do |message|
    File.write(File.join(history, "app.txt"), message)
    git.call("add", "app.txt")
    git.call("commit", "--quiet", "-m", message)
    git.call("rev-parse", "HEAD")
  end
  commit.call("Submitted 4.1.0")
  git.call("tag", "v4.1.0")
  git.call("push", "--quiet", "--tags", "origin", "HEAD:main")
  File.write(File.join(bin, "dart"), <<~SH)
    #!/bin/sh
    [ "$*" = "run cider version" ] || exit 1
    printf '%s\\n' "$CIDER_TEST_VERSION"
  SH
  FileUtils.chmod(0o755, File.join(bin, "dart"))
  number_build = lambda do |version, event = "push"|
    output = File.join(temporary, "build-output")
    environment = File.join(temporary, "build-environment")
    File.write(output, "")
    File.write(environment, "")
    run_command({
      "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
      "CIDER_TEST_VERSION" => version,
      "GITHUB_RUN_NUMBER" => "100", "GITHUB_RUN_ATTEMPT" => "1",
      "GITHUB_EVENT_NAME" => event, "GITHUB_OUTPUT" => output,
      "GITHUB_ENV" => environment
    }, "bash", "-e", "-o", "pipefail", "-c", script, chdir: history)
    [output, environment].flat_map { |path| File.readlines(path, chomp: true) }
                         .to_h { |line| line.split("=", 2) }
  end
  assert(number_build.call("4.1.0")["BUILD_ANDROID"] == "false", "Submitted versions skip Android")
  assert(number_build.call("4.1.0", "workflow_dispatch")["BUILD_ANDROID"] == "true",
         "Manual artifact builds remain available")
  major = commit.call("Pending major 5.0.0")
  assert(number_build.call("5.0.0")["previous_version"] == "4.1.0", "Major baseline changed")
  commit.call("Backend-only merge while the major is pending")
  assert(number_build.call("5.0.0")["previous_version"] == "4.1.0", "Backend merge lost major intent")
  commit.call("Pending patch 5.0.1")
  assert(number_build.call("5.0.1")["previous_version"] == "4.1.0", "Unsubmitted patch lost major intent")
  git.call("tag", "v5.0.0", major)
  assert(number_build.call("5.0.1")["previous_version"] == "5.0.0", "Submitted major must reset patch baseline")
  git.call("tag", "v5.0.1")
  assert(number_build.call("5.0.1")["app_release"] == "false", "Submitted patch must not upload again")
  puts "Fastlane priority mapping, upload configuration and release tag selection passed."
ensure
  ENV.replace(original_environment)
  FileUtils.remove_entry(temporary)
  assert(!File.exist?(temporary), "Temporary Fastlane project was not removed")
end
