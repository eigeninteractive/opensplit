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
    en-US/title.txt
    en-US/short_description.txt
    en-US/full_description.txt
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
  ENV["PLAY_UPDATE_LISTING"] = "true"

  Dir.chdir(temporary) do
    fastfile = Fastlane::FastFile.new("fastlane/Fastfile")
    fastfile.runner.execute(:closed, :android)
    assert(uploads.size == 1, "Expected one captured upload")
    options = uploads.last
    assert(options[:metadata_path] == metadata, "Metadata path changed with Fastlane's working directory")
    assert(options[:track] == "alpha", "Release should go to closed testing")
    assert(options[:skip_upload_metadata] == false, "Changed listing text must be uploaded")
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

    # An app-only release must not resubmit unchanged listing content.
    ENV["PLAY_UPDATE_LISTING"] = "false"
    fastfile.runner.execute(:production, :android)
    options = uploads.last
    %i[skip_upload_metadata skip_upload_images skip_upload_screenshots].each do |key|
      assert(options[key], "App-only releases must set #{key}")
    end
    assert(options[:skip_upload_changelogs] == false, "App-only releases still update What's new")
    assert(options[:skip_upload_aab] == false, "App-only releases still upload the bundle")
    ENV["PLAY_UPDATE_LISTING"] = "invalid"
    refuses_upload(fastfile, uploads, :production, "PLAY_UPDATE_LISTING")
    ENV["PLAY_UPDATE_LISTING"] = "true"

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

    # Store edits do not need an AAB, release notes, version bump or priority.
    File.delete(File.join(metadata, "en-US/changelogs/default.txt"))
    ENV["PLAY_APP_VERSION"] = "invalid"
    ENV["PLAY_UPDATE_PRIORITY"] = "invalid"
    fastfile.runner.execute(:listing, :android)
    options = uploads.last
    assert(options[:skip_upload_aab] && options[:skip_upload_apk], "Listing-only uploads must skip all binaries")
    assert(options[:aab].nil? && options[:apk].nil?, "Listing-only uploads must not name a binary")
    assert(options[:skip_upload_changelogs], "Listing-only uploads must preserve What's new")
    assert(options[:skip_upload_metadata] == false, "Listing-only uploads must update copy")
    assert(options[:track_promote_to].nil? && options[:rollout].nil?, "Store edits must not promote or roll out builds")
    File.delete(File.join(metadata, "en-US/title.txt"))
    refuses_upload(fastfile, uploads, :listing, "PLAY_METADATA_DIR")
    File.write(File.join(metadata, "en-US/title.txt"), "OpenSplit")

    File.write(bundle, "test bundle")
    ENV["PLAY_APP_VERSION"] = "4.1.1"
    ENV["PLAY_UPDATE_PRIORITY"] = "0"
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
    File.write(output, "")
    run_command({
      "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
      "CIDER_TEST_VERSION" => version,
      "GITHUB_RUN_NUMBER" => "100", "GITHUB_RUN_ATTEMPT" => "1",
      "GITHUB_EVENT_NAME" => event, "GITHUB_OUTPUT" => output
    }, "bash", "-e", "-o", "pipefail", "-c", script, chdir: history)
    File.readlines(output, chomp: true).to_h { |line| line.split("=", 2) }
  end
  assert(number_build.call("4.1.0")["build_android"] == "false", "Submitted versions skip Android")
  assert(number_build.call("4.1.0", "workflow_dispatch")["build_android"] == "true",
         "Manual artifact builds remain available")
  major = commit.call("Pending major 5.0.0")
  assert(number_build.call("5.0.0")["build_android"] == "true", "Pending versions build Android")
  assert(number_build.call("5.0.0")["previous_version"] == "4.1.0", "Major baseline changed")
  commit.call("Backend-only merge while the major is pending")
  assert(number_build.call("5.0.0")["previous_version"] == "4.1.0", "Backend merge lost major intent")
  commit.call("Pending patch 5.0.1")
  assert(number_build.call("5.0.1")["previous_version"] == "4.1.0", "Unsubmitted patch lost major intent")
  git.call("tag", "v5.0.0", major)
  assert(number_build.call("5.0.1")["previous_version"] == "5.0.0", "Submitted major must reset patch baseline")
  git.call("tag", "v5.0.1")
  assert(number_build.call("5.0.1")["app_release"] == "false", "Submitted patch must not upload again")

  # Listing changes are compared with the last successful deployment. A failed
  # listing edit followed by a backend-only merge must still be published.
  listing_script = steps.find { |step| step["name"] == "Check for Play listing changes" }.fetch("run")
  File.write(File.join(bin, "gh"), <<~SH)
    #!/bin/sh
    case "$*" in
      *'event=push&status=success'*) printf '%s\\n' "$LISTING_TEST_BASELINE" ;;
      *) exit 1 ;;
    esac
  SH
  FileUtils.chmod(0o755, File.join(bin, "gh"))
  listing_changed = lambda do |baseline|
    output = File.join(temporary, "listing-output")
    File.write(output, "")
    run_command({
      "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
      "LISTING_TEST_BASELINE" => baseline,
      "GITHUB_REPOSITORY" => "example/opensplit", "GITHUB_OUTPUT" => output
    }, "bash", "-e", "-o", "pipefail", "-c", listing_script, chdir: history)
    File.read(output).strip == "changed=true"
  end
  previous = git.call("rev-parse", "HEAD")
  assert(listing_changed.call(""), "First sync must publish the listing")
  assert(!listing_changed.call(previous), "Identical content must not be resubmitted")
  commit.call("App release with unchanged listing")
  assert(!listing_changed.call(previous), "App-only changes must leave the listing alone")
  %w[
    fastlane/metadata/android/en-US/title.txt
    fastlane/metadata/android/en-US/short_description.txt
    fastlane/metadata/android/en-US/full_description.txt
    site/store/play/screenshot-1-groups.png
    site/store/feature-graphic.jpg
    assets/icon/icon.png
  ].each do |path|
    previous = git.call("rev-parse", "HEAD")
    target = File.join(history, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "changed listing content")
    git.call("add", path)
    git.call("commit", "--quiet", "-m", "Update #{path}")
    assert(listing_changed.call(previous), "#{path} must trigger a listing upload")
    commit.call("Backend-only merge after failed #{path} upload")
    assert(listing_changed.call(previous), "Pending #{path} must survive subsequent merges")
    assert(!listing_changed.call(git.call("rev-parse", "HEAD")), "Successful listing sync must stop retries")
  end
  puts "Fastlane app/listing uploads, priority mapping and deployment change detection passed."
ensure
  ENV.replace(original_environment)
  FileUtils.remove_entry(temporary)
  assert(!File.exist?(temporary), "Temporary Fastlane project was not removed")
end
