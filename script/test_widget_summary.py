#!/usr/bin/env python3
"""Check Xcode's actual widget metadata; desktop acceptance is a separate check."""
import argparse
import itertools
import json
from pathlib import Path


def visible(summary, values):
    if 'actionSummary' in summary:
        return set(summary['actionSummary']['wrapper']['otherParameterIdentifiers'])
    clause = summary['whenClause']['wrapper']
    condition = clause['condition']
    actual = values.get(condition['parameterIdentifier'])
    operator = condition['comparisonOperator']
    if operator == 8:  # HasValueComparisonOperator.hasNoValue
        matches = actual is None or actual == []
    elif operator == 0:  # HasValueComparisonOperator.hasAnyValue
        matches = actual is not None and actual != []
    elif operator in (1, 2):  # notEqualTo / equalTo
        expected = next(iter(condition['value'].values()))['value']
        matches = actual == expected
        if operator == 1:
            matches = not matches
    else:
        raise AssertionError(f'Unexpected metadata condition: {condition}')
    return visible(clause['when'] if matches else clause['otherwise'], values)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    files = list((args.app/'Contents/PlugIns').rglob('extract.actionsdata'))
    assert len(files) == 1
    intent = json.loads(files[0].read_bytes())['actions']['SelectEventIntent']
    summary = intent['actionConfiguration']
    flags = {'showTargetDate', 'showIcon', 'showClock'}
    slots = {'mediumEvent1ID', 'mediumEvent2ID', 'mediumEvent3ID'}
    legacy = {'dateScope', 'includedTags', 'tagMatch', 'excludedTags', 'sortOrder', 'prioritizePinned', 'skipCount'}
    legacy_values = [
        {}, {'showAdvancedFilters': True}, {'dateScope': 'past'},
        {'includedTags': ['Work']}, {'excludedTags': ['Private']},
        {'sortOrder': 'nearest'}, {'prioritizePinned': False}, {'skipCount': 1},
    ]
    cases = 0
    for size, event, manual, appearance, source, custom in itertools.product(
            ['systemSmall', 'systemMedium', 'systemLarge'],
            ['automatic', None, 'event-uuid'], [False, True],
            ['standard', 'compact', 'custom', None], ['events', 'smartList'], legacy_values):
        values = {'system.widgetFamily': size, 'eventID': event, 'contentSource': source,
                  'appearance': appearance, 'manualMediumSelection': manual,
                  'showAdvancedFilters': False, 'dateScope': 'all', 'includedTags': [],
                  'excludedTags': [], 'skipCount': 0, 'sortOrder': 'automatic', 'prioritizePinned': True}
        values.update(custom)
        expected = {'contentSource', 'appearance'}
        if appearance in ('custom', None):
            expected |= flags
        if source == 'smartList':
            expected |= {'smartListID'}
            if size == 'systemLarge': expected |= {'largePageSize'}
        elif size == 'systemSmall':
            expected |= {'eventID'}
        elif size == 'systemMedium' and manual:
            expected |= slots | {'manualMediumSelection'}
        elif event == 'event-uuid':
            expected |= {'eventID'}
            if size == 'systemMedium': expected |= {'manualMediumSelection'}
        else:
            expected |= {'eventID', 'showAdvancedFilters'}
            expected |= {'manualMediumSelection'} if size == 'systemMedium' else {'largePageSize'}
            if custom: expected |= legacy
        shown = visible(summary, values)
        assert shown == expected, (values, shown, expected)
        cases += 1
    # WidgetKit displays the extracted declaration order, not Summary's reference order.
    parameter_order = [p['name'] for p in intent['parameters']]
    expected_order = ['contentSource', 'eventID', 'smartListID', 'manualMediumSelection',
        'mediumEvent1ID', 'mediumEvent2ID', 'mediumEvent3ID', 'largePageSize', 'appearance',
        'showIcon', 'showTargetDate', 'showClock', 'showAdvancedFilters', 'dateScope',
        'includedTags', 'tagMatch', 'excludedTags', 'sortOrder', 'prioritizePinned', 'skipCount']
    assert parameter_order == expected_order, ('Widget controls in wrong order', parameter_order)
    appearance = next(p for p in intent['parameters'] if p['name'] == 'appearance')
    assert appearance['isOptional'] is True
    assert appearance['typeSpecificMetadata'] == ['LNValueTypeSpecificMetadataKeyDefaultValue',
        {'string': {'wrapper': 'custom'}}], ('Legacy appearance needs an explicit preserving default', appearance)
    parameter_names = {p['name'] for p in intent['parameters']}
    assert parameter_names == flags | slots | legacy | {'eventID', 'showAdvancedFilters', 'largePageSize',
        'manualMediumSelection', 'contentSource', 'appearance', 'smartListID'}
    print(f'Xcode widget metadata: {cases} size/source/appearance/legacy combinations PASS; all 17 old IDs preserved')


if __name__ == '__main__':
    main()
