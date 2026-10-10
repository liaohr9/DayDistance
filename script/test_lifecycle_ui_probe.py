#!/usr/bin/env python3
"""Refuse a QA entrypoint that could still initialize the real event repository."""
from pathlib import Path
import unittest
from lifecycle_ui_probe import lifecycle_source

SOURCE = (Path(__file__).resolve().parent.parent / 'App/DayDistanceApp.swift').read_text()
STORE = 'let initialStore = EventStore(automaticallyLoad: false)'
SCENE = '.defaultSize(width: 800, height: 520)'
QA_STORE = 'let initialStore = LifecycleProbeRepository.makeStore()'
QA_SCENE = SCENE + '\n        .commands { LifecycleProbeCommands() }'


class LifecycleHostTests(unittest.TestCase):
    def test_uses_real_app_and_menus_with_only_temporary_store_and_qa_commands(self):
        host = lifecycle_source(SOURCE)
        self.assertNotIn('EventStore(automaticallyLoad: false)', host)
        self.assertEqual(host.replace(QA_STORE, STORE).replace(QA_SCENE, SCENE).replace('repositoryProvider: { EventRepository(fileURL: LifecycleProbeRepository.root.appendingPathComponent("data/events.json")) }', 'repositoryProvider: { try SharedContainer.repository() }'), SOURCE)
        self.assertIn(QA_STORE, host)
        self.assertIn(QA_SCENE, host)

    def test_refuses_missing_or_multiple_store_anchors(self):
        for source in (SOURCE.replace(STORE, ''), SOURCE + '\n' + STORE):
            with self.subTest(source=source[-60:]):
                with self.assertRaises(ValueError):
                    lifecycle_source(source)

    def test_refuses_an_additional_default_repository_initializer(self):
        with self.assertRaises(ValueError):
            lifecycle_source(SOURCE + '\nlet unsafe = EventStore()\n')

    def test_refuses_changed_or_multiple_scene_anchors(self):
        for source in (SOURCE.replace(SCENE, ''), SOURCE + '\n' + SCENE):
            with self.subTest(source=source[-60:]):
                with self.assertRaises(ValueError):
                    lifecycle_source(source)


if __name__ == '__main__':
    unittest.main()
