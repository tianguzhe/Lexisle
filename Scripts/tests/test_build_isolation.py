"""Build-isolation boundaries, without changing macOS application registration."""

import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "build_isolation.py"
SPEC = importlib.util.spec_from_file_location("build_isolation", SCRIPT)
isolation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(isolation)


class BuildIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="build isolation tests ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.project = self.base / "Project With Spaces"
        self.project.mkdir()
        self.derived_data_home = self.base / "Global DerivedData"
        self.derived_data_home.mkdir()
        self.area = self.make_area()

    def make_area(self, **kwargs):
        return isolation.BuildArea(self.project, derived_data_home=self.derived_data_home, **kwargs)

    def derived_data(self, name, workspace):
        directory = self.derived_data_home / name
        directory.mkdir()
        (directory / "info.plist").write_bytes(plistlib.dumps({"WorkspacePath": str(workspace)}))
        return directory

    def xcode_settings(self, container):
        workspace = container / "project.xcworkspace" if container.suffix == ".xcodeproj" else container
        return workspace / "xcuserdata/isolation-test-user.xcuserdatad/WorkspaceSettings.xcsettings"

    def test_prepare_creates_per_user_settings_for_projects_and_workspaces(self):
        containers = [self.project / "Example App.xcodeproj", self.project / "Example Workspace.xcworkspace"]
        for container in containers:
            container.mkdir()
        with patch.object(isolation.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="isolation-test-user")):
            self.area.prepare()
        for container in containers:
            with self.subTest(container=container):
                settings = self.xcode_settings(container)
                configuration = plistlib.loads(settings.read_bytes())
                self.assertEqual(configuration["DerivedDataLocationStyle"], "WorkspaceRelativePath")
                self.assertEqual(configuration["DerivedDataCustomLocation"], ".build/artifacts.noindex/Xcode")
                self.assertEqual(configuration["BuildLocationStyle"], "UniqueDerivedDataSubfolder")
                self.assertFalse((settings.parents[2] / "xcshareddata/WorkspaceSettings.xcsettings").exists())

    def test_prepare_preserves_unrelated_user_preferences_and_is_idempotent(self):
        container = self.project / "Example.xcodeproj"
        settings = self.xcode_settings(container)
        settings.parent.mkdir(parents=True)
        original = {
            "BuildLocationStyle": "CustomLocation",
            "DerivedDataLocationStyle": "AbsolutePath",
            "DerivedDataCustomLocation": str(self.base / "Old Cache"),
            "BuildSystemType": "Latest",
            "IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded": False,
            "UnrelatedPreference": {"enabled": True, "values": [1, 2]},
        }
        settings.write_bytes(plistlib.dumps(original))
        with patch.object(isolation.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="isolation-test-user")):
            self.area.prepare()
            updated = plistlib.loads(settings.read_bytes())
            for key in ["BuildSystemType", "IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded", "UnrelatedPreference"]:
                self.assertEqual(updated[key], original[key])
            self.assertEqual(updated["BuildLocationStyle"], "UniqueDerivedDataSubfolder")
            self.assertEqual(updated["DerivedDataLocationStyle"], "WorkspaceRelativePath")
            self.assertEqual(updated["DerivedDataCustomLocation"], ".build/artifacts.noindex/Xcode")
            with patch.object(Path, "write_bytes", side_effect=AssertionError("Unchanged settings were rewritten")):
                self.area.prepare()

    def test_xcode_settings_file_symlink_cannot_modify_external_preferences(self):
        container = self.project / "Example.xcodeproj"
        settings = self.xcode_settings(container)
        settings.parent.mkdir(parents=True)
        outside = self.base / "ExternalPreferences.plist"
        original = plistlib.dumps({"PersonalSetting": "keep"})
        outside.write_bytes(original)
        settings.symlink_to(outside)
        with patch.object(isolation.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="isolation-test-user")):
            with self.assertRaises(ValueError):
                self.area.prepare()
        self.assertEqual(outside.read_bytes(), original)

    def test_xcode_settings_parent_symlink_cannot_create_external_files(self):
        container = self.project / "Example.xcodeproj"
        workspace = container / "project.xcworkspace"
        workspace.mkdir(parents=True)
        outside = self.base / "ExternalUserData"
        outside.mkdir()
        (workspace / "xcuserdata").symlink_to(outside, target_is_directory=True)
        with patch.object(isolation.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="isolation-test-user")):
            with self.assertRaises(ValueError):
                self.area.prepare()
        self.assertEqual(list(outside.iterdir()), [])

    def test_installed_and_unrelated_app_paths_are_never_owned(self):
        owned = self.project / ".build/artifacts.noindex/Example App.app"
        owned.mkdir(parents=True)
        self.assertTrue(self.area.owns(owned))
        for path in [
            Path("/Applications/Example App.app"),
            Path.home() / "Applications/Example App.app",
            Path("/Volumes/Example Installer/Example App.app"),
            self.base / "Other Project/.build/Example App.app",
            self.project / "dist/Example App.app",
            self.project / ".build/Example App.dmg",
        ]:
            with self.subTest(path=path):
                self.assertFalse(self.area.owns(path))

    def test_build_app_and_parent_symlinks_cannot_escape_scope(self):
        installed = self.base / "Installed/Example App.app"
        installed.mkdir(parents=True)
        self.area.build.mkdir()
        bundle_link = self.area.build / "Alias.app"
        bundle_link.symlink_to(installed, target_is_directory=True)
        directory_link = self.area.build / "external"
        directory_link.symlink_to(installed.parent, target_is_directory=True)
        self.assertFalse(self.area.owns(bundle_link))
        self.assertFalse(self.area.owns(directory_link / installed.name))
        self.assertFalse(self.area.owns(self.area.build / ".." / "dist/Example App.app"))

    def test_top_level_build_symlink_is_rejected_before_prepare(self):
        outside = self.base / "External Cache"
        outside.mkdir()
        self.area.build.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.make_area()
        self.assertEqual(list(outside.iterdir()), [])

    def test_stale_registered_apps_are_parsed_without_existing_files(self):
        stale = self.project / ".build/Old Cache/Example App.app"
        dump = "\n".join([
            f"path: {stale} (0x123ABC)",
            f"path: {stale}",
            f"name: {self.project}/.build/Not A Path.app",
            "path: relative/Not Absolute.app",
            f"path: {self.project}/.build/Example.framework",
        ])
        self.assertFalse(stale.exists())
        self.assertEqual(isolation.registered_paths(dump), {stale})
        self.assertTrue(self.area.owns(stale))

    def test_registry_cleanup_only_unregisters_scoped_paths(self):
        stale = self.project / ".build/Old Product.app"
        installed = Path("/Applications/Example App.app")
        unrelated = self.base / "Another Project/.build/Example App.app"
        dump = "\n".join(f"path: {path}" for path in [installed, stale, unrelated])
        results = [
            subprocess.CompletedProcess(["lsregister", "-dump"], 0, stdout=dump, stderr=""),
            subprocess.CompletedProcess(["lsregister", "-u"], 0, stdout="", stderr=""),
        ]
        with patch.object(isolation.subprocess, "run", side_effect=results) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                self.area.cleanup()
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[1].args[0], [str(isolation.LSREGISTER), "-u", str(stale)])

    def test_dry_run_reads_registry_without_unregistering(self):
        app = self.area.build / "Cached.app"
        result = subprocess.CompletedProcess(["lsregister"], 0, stdout=f"path: {app}", stderr="")
        with patch.object(isolation.subprocess, "run", return_value=result) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                self.area.cleanup(dry_run=True)
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0], [str(isolation.LSREGISTER), "-dump"])

    def test_global_derived_data_requires_workspace_inside_exact_project(self):
        owned = self.derived_data("Unrelated-Looking-Cache", self.project / "App.xcodeproj/project.xcworkspace")
        other = self.derived_data("App-Same-Name", self.base / "Other/App.xcodeproj/project.xcworkspace")
        prefix_collision = self.derived_data("Prefix-Collision", Path(str(self.project) + "-copy") / "App.xcodeproj")
        not_workspace = self.derived_data("Invalid-Workspace", self.project / "notes.txt")
        malformed = self.derived_data_home / "Broken-Cache"
        malformed.mkdir()
        (malformed / "info.plist").write_text("not a plist")
        area = self.make_area()
        self.assertTrue(area.owns(owned / "Build/Products/Debug/Example.app"))
        for directory in [other, prefix_collision, not_workspace, malformed]:
            with self.subTest(directory=directory):
                self.assertFalse(area.owns(directory / "Build/Products/Debug/Example.app"))

    def test_invalid_global_derived_data_metadata_is_ignored(self):
        records = [[], {"WorkspacePath": 42}, {}, {"WorkspacePath": "Relative.xcodeproj"}]
        for index, metadata in enumerate(records):
            directory = self.derived_data_home / f"Invalid-{index}"
            directory.mkdir()
            (directory / "info.plist").write_bytes(plistlib.dumps(metadata))
        area = self.make_area()
        for directory in self.derived_data_home.iterdir():
            self.assertFalse(area.owns(directory / "Build/Products/Example.app"))

    def test_xcode_command_injects_isolated_path_and_environment(self):
        arguments, environment = self.area.command(
            ["/usr/bin/xcodebuild", "-project", "Example.xcodeproj", "build"], "mac-debug"
        )
        expected = self.area.work / "xcode/mac-debug"
        self.assertEqual(arguments[:3], ["/usr/bin/xcodebuild", "-derivedDataPath", str(expected)])
        self.assertEqual(environment["ISOLATED_BUILD_DIR"], str(self.area.work))
        self.assertEqual(environment["ISOLATED_DERIVED_DATA"], str(expected))
        self.assertEqual(environment["ISOLATED_LOG_DIR"], str(self.area.work / "logs"))

    def test_xcrun_xcodebuild_receives_same_isolated_path(self):
        arguments, environment = self.area.command(["xcrun", "xcodebuild", "build"], "ios")
        expected = self.area.work / "xcode/ios"
        self.assertEqual(arguments[:4], ["xcrun", "xcodebuild", "-derivedDataPath", str(expected)])
        self.assertEqual(environment["ISOLATED_DERIVED_DATA"], str(expected))

    def test_other_xcode_output_overrides_cannot_write_outside_isolation(self):
        outside = str(self.base / "External Products")
        for option in ["-archivePath", "-resultBundlePath"]:
            with self.subTest(option=option):
                with self.assertRaises(ValueError):
                    self.area.command(["xcodebuild", option, outside, "build"], "mac")
        for setting in ["SYMROOT", "OBJROOT", "DSTROOT", "CONFIGURATION_BUILD_DIR", "CONFIGURATION_TEMP_DIR"]:
            with self.subTest(setting=setting):
                with self.assertRaises(ValueError):
                    self.area.command(["xcodebuild", f"{setting}={outside}", "build"], "mac")

    def test_explicit_derived_data_must_remain_under_noindex_root(self):
        inside = ".build/artifacts.noindex/custom/DerivedData"
        arguments, environment = self.area.command(["xcodebuild", "-derivedDataPath", inside, "build"], "mac")
        self.assertEqual(arguments.count("-derivedDataPath"), 1)
        self.assertEqual(environment["ISOLATED_DERIVED_DATA"], str(self.project / inside))
        for outside in [str(self.base / "Outside"), "build/DerivedData", ".build/artifacts.noindex/../../outside"]:
            with self.subTest(outside=outside):
                with self.assertRaises(ValueError):
                    self.area.command(["xcodebuild", "-derivedDataPath", outside, "build"], "mac")

    def test_duplicate_derived_data_override_cannot_escape(self):
        with self.assertRaises(ValueError):
            self.area.command([
                "xcodebuild", "-derivedDataPath", str(self.area.work / "mac"),
                "-derivedDataPath", str(self.base / "Outside"), "build",
            ], "mac")

    def test_default_derived_data_rejects_escaping_symlink(self):
        self.area.prepare()
        outside = self.base / "External Cache"
        outside.mkdir()
        (self.area.work / "xcode").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.area.command(["xcodebuild", "build"], "mac")

    def test_explicit_derived_data_rejects_escaping_symlink(self):
        self.area.prepare()
        outside = self.base / "External Cache"
        outside.mkdir()
        link = self.area.work / "legacy"
        link.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.area.command(["xcodebuild", "-derivedDataPath", str(link / "DerivedData"), "build"], "mac")

    def test_cleanup_rechecks_scope_if_app_becomes_a_symlink(self):
        app = self.area.build / "Cached.app"
        app.mkdir(parents=True)
        outside = self.base / "Installed.app"
        outside.mkdir()

        def changed_registry_snapshot():
            app.rmdir()
            app.symlink_to(outside, target_is_directory=True)
            return [app]

        with patch.object(self.area, "registered", side_effect=changed_registry_snapshot):
            with patch.object(isolation.subprocess, "run") as run:
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError):
                        self.area.cleanup()
        run.assert_not_called()
        self.assertTrue(outside.is_dir())

    def test_exec_cleanup_runs_after_failed_child_and_preserves_status(self):
        with patch.object(isolation.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = 23
            with patch.object(isolation.signal, "signal", return_value=signal.SIG_DFL):
                with patch.object(self.area, "cleanup") as cleanup:
                    code = isolation.execute(self.area, ["fake-build", "--fail"], "mac")
        self.assertEqual(code, 23)
        cleanup.assert_called_once_with()
        self.assertEqual(popen.call_args.kwargs["cwd"], self.project)

    def test_cleanup_failure_does_not_mask_failed_child(self):
        with patch.object(isolation.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = 17
            with patch.object(isolation.signal, "signal", return_value=signal.SIG_DFL):
                with patch.object(self.area, "cleanup", side_effect=RuntimeError("registry unavailable")):
                    with contextlib.redirect_stderr(io.StringIO()) as errors:
                        code = isolation.execute(self.area, ["fake-build"], "mac")
        self.assertEqual(code, 17)
        self.assertIn("Cleanup failed", errors.getvalue())

    def test_successful_child_reports_cleanup_failure(self):
        with patch.object(isolation.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = 0
            with patch.object(isolation.signal, "signal", return_value=signal.SIG_DFL):
                with patch.object(self.area, "cleanup", side_effect=RuntimeError("registry unavailable")):
                    with contextlib.redirect_stderr(io.StringIO()):
                        code = isolation.execute(self.area, ["fake-build"], "mac")
        self.assertEqual(code, 1)

    def test_terminated_child_status_is_reported_after_cleanup(self):
        with patch.object(isolation.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = -signal.SIGTERM
            with patch.object(isolation.signal, "signal", return_value=signal.SIG_DFL):
                with patch.object(self.area, "cleanup") as cleanup:
                    code = isolation.execute(self.area, ["fake-build"], "mac")
        self.assertEqual(code, 128 + signal.SIGTERM)
        cleanup.assert_called_once_with()

    def test_cleanup_runs_when_child_cannot_launch(self):
        with patch.object(isolation.subprocess, "Popen", side_effect=FileNotFoundError("missing compiler")):
            with patch.object(isolation.signal, "signal", return_value=signal.SIG_DFL):
                with patch.object(self.area, "cleanup") as cleanup:
                    with self.assertRaises(FileNotFoundError):
                        isolation.execute(self.area, ["missing-compiler"], "mac")
        cleanup.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
