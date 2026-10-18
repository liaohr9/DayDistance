import AppIntents
import Foundation
import OSLog

// Store a primitive ID: local ad hoc builds cannot resolve AppEntity identities.
// Display labels are separate so duplicate names and renames keep the right event.
struct EventOptionsProvider: DynamicOptionsProvider {
    func defaultResult() async -> String? { "automatic" }
    func results() async throws -> IntentItemCollection<String> {
        let events = try SharedContainer.repository().load()
        let automatic = IntentItem<String>("automatic", title: LocalizedStringResource("自动选择"), subtitle: LocalizedStringResource("小号显示最近日子，中大号显示筛选概览"))
        let eventItems = WidgetPolicy.sorted(events: events, now: Date()).map { event in
            IntentItem<String>(event.id.uuidString, title: "\(event.title)", subtitle: "\(event.dateLabel(now: Date()))")
        }
        Logger(subsystem: "local.daydistance.mac", category: "widget").info("Event options loaded \(events.count) events")
        return IntentItemCollection(sections: [IntentItemSection(items: [automatic]), IntentItemSection("单个事件", items: eventItems)])
    }
}

struct ManualEventOptionsProvider: DynamicOptionsProvider {
    func defaultResult() async -> String? { WidgetManualSelection.noSelectionID }
    func results() async throws -> IntentItemCollection<String> {
        let events = try SharedContainer.repository().load()
        let none = IntentItem<String>(WidgetManualSelection.noSelectionID, title: LocalizedStringResource("不选择"))
        let items = [none] + WidgetPolicy.sorted(events: events, now: Date()).map { event in
            IntentItem<String>(event.id.uuidString, title: "\(event.title)", subtitle: "\(event.dateLabel(now: Date()))")
        }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct SelectEventIntent: WidgetConfigurationIntent {
    static var title = LocalizedStringResource("选择一个日子")
    static var description = IntentDescription(LocalizedStringResource("小号默认显示最近日子；中大号可独立筛选概览。也可以指定一个事件。"))
    @Parameter(title: "内容来源", default: .events)
    var contentSource: WidgetContentSource
    @Parameter(title: LocalizedStringResource("显示内容"), optionsProvider: EventOptionsProvider())
    var eventID: String?
    @Parameter(title: "智能列表", optionsProvider: SmartListOptionsProvider())
    var smartListID: String?
    @Parameter(title: LocalizedStringResource("中号手动选择事件"), default: false)
    var manualMediumSelection: Bool
    @Parameter(title: LocalizedStringResource("中号第一个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent1ID: String?
    @Parameter(title: LocalizedStringResource("中号第二个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent2ID: String?
    @Parameter(title: LocalizedStringResource("中号第三个事件"), optionsProvider: ManualEventOptionsProvider())
    var mediumEvent3ID: String?
    @Parameter(title: "大号每页条数", default: 6, inclusiveRange: (5, 10))
    var largePageSize: Int
    @Parameter(title: "外观", default: .custom)
    var appearance: WidgetAppearance?
    @Parameter(title: LocalizedStringResource("显示事件图标"), default: true)
    var showIcon: Bool
    @Parameter(title: LocalizedStringResource("显示目标日期"), default: true)
    var showTargetDate: Bool
    @Parameter(title: LocalizedStringResource("显示当天精确计时"), default: true)
    var showClock: Bool
    @Parameter(title: "原有筛选选项", description: "保留旧版自动概览的条件；新规则请在日距中创建智能列表。", default: false)
    var showAdvancedFilters: Bool
    @Parameter(title: "显示范围", default: .all)
    var dateScope: WidgetDateScope
    @Parameter(title: "包含标签", optionsProvider: TagOptionsProvider())
    var includedTags: [String]
    @Parameter(title: "标签匹配", default: .all)
    var tagMatch: WidgetTagMatch
    @Parameter(title: "排除标签", optionsProvider: TagOptionsProvider())
    var excludedTags: [String]
    @Parameter(title: "组件排序", default: .automatic)
    var sortOrder: WidgetSort
    @Parameter(title: "优先置顶", default: true)
    var prioritizePinned: Bool
    @Parameter(title: "跳过前几条", default: 0, inclusiveRange: (0, 999))
    var skipCount: Int
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemSmall) {
            When(\.$contentSource, .equalTo, WidgetContentSource.smartList) {
                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                    Summary {
                        \.$contentSource
                        \.$smartListID
                        \.$appearance
                    }
                } otherwise: {
                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                        Summary {
                            \.$contentSource
                            \.$smartListID
                            \.$appearance
                        }
                    } otherwise: {
                        Summary {
                            \.$contentSource
                            \.$smartListID
                            \.$appearance
                            \.$showTargetDate
                            \.$showIcon
                            \.$showClock
                        }
                    }
                }
            } otherwise: { When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                    Summary {
                        \.$contentSource
                        \.$eventID
                        \.$appearance
                    }
                } otherwise: {
                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                        Summary {
                            \.$contentSource
                            \.$eventID
                            \.$appearance
                        }
                    } otherwise: {
                        Summary {
                            \.$contentSource
                            \.$eventID
                            \.$appearance
                            \.$showTargetDate
                            \.$showIcon
                            \.$showClock
                        }
                    }
                } }
        } otherwise: {
            When(widgetFamily: .equalTo, .systemMedium) {
                When(\.$contentSource, .equalTo, WidgetContentSource.smartList) {
                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                        Summary {
                            \.$contentSource
                            \.$smartListID
                            \.$appearance
                        }
                    } otherwise: {
                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                            Summary {
                                \.$contentSource
                                \.$smartListID
                                \.$appearance
                            }
                        } otherwise: {
                            Summary {
                                \.$contentSource
                                \.$smartListID
                                \.$appearance
                                \.$showTargetDate
                                \.$showIcon
                                \.$showClock
                            }
                        }
                    }
                } otherwise: {
                    When(\.$manualMediumSelection, .equalTo, true) {
                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                            Summary {
                                \.$contentSource
                                \.$manualMediumSelection
                                \.$mediumEvent1ID
                                \.$mediumEvent2ID
                                \.$mediumEvent3ID
                                \.$appearance
                            }
                        } otherwise: {
                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                Summary {
                                    \.$contentSource
                                    \.$manualMediumSelection
                                    \.$mediumEvent1ID
                                    \.$mediumEvent2ID
                                    \.$mediumEvent3ID
                                    \.$appearance
                                }
                            } otherwise: {
                                Summary {
                                    \.$contentSource
                                    \.$manualMediumSelection
                                    \.$mediumEvent1ID
                                    \.$mediumEvent2ID
                                    \.$mediumEvent3ID
                                    \.$appearance
                                    \.$showTargetDate
                                    \.$showIcon
                                    \.$showClock
                                }
                            }
                        }
                    } otherwise: {
                        When(\.$eventID, .equalTo, "automatic") {
                            When(\.$showAdvancedFilters, .equalTo, true) {
                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$manualMediumSelection
                                        \.$showAdvancedFilters
                                        \.$dateScope
                                        \.$includedTags
                                        \.$tagMatch
                                        \.$excludedTags
                                        \.$sortOrder
                                        \.$prioritizePinned
                                        \.$skipCount
                                        \.$appearance
                                    }
                                } otherwise: {
                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$appearance
                                            \.$showTargetDate
                                            \.$showIcon
                                            \.$showClock
                                        }
                                    }
                                }
                            } otherwise: {
                                When(\.$dateScope, .notEqualTo, WidgetDateScope.all) {
                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                                \.$showTargetDate
                                                \.$showIcon
                                                \.$showClock
                                            }
                                        }
                                    }
                                } otherwise: {
                                    When(\.$includedTags, .hasAnyValue) {
                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                    \.$showTargetDate
                                                    \.$showIcon
                                                    \.$showClock
                                                }
                                            }
                                        }
                                    } otherwise: {
                                        When(\.$excludedTags, .hasAnyValue) {
                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                        \.$showTargetDate
                                                        \.$showIcon
                                                        \.$showClock
                                                    }
                                                }
                                            }
                                        } otherwise: {
                                            When(\.$sortOrder, .notEqualTo, WidgetSort.automatic) {
                                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                            \.$showTargetDate
                                                            \.$showIcon
                                                            \.$showClock
                                                        }
                                                    }
                                                }
                                            } otherwise: {
                                                When(\.$prioritizePinned, .equalTo, false) {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                                \.$showTargetDate
                                                                \.$showIcon
                                                                \.$showClock
                                                            }
                                                        }
                                                    }
                                                } otherwise: {
                                                    When(\.$skipCount, .notEqualTo, 0) {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$appearance
                                                                    \.$showTargetDate
                                                                    \.$showIcon
                                                                    \.$showClock
                                                                }
                                                            }
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$appearance
                                                                    \.$showTargetDate
                                                                    \.$showIcon
                                                                    \.$showClock
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } otherwise: {
                            When(\.$eventID, .hasNoValue) { When(\.$showAdvancedFilters, .equalTo, true) {
                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                                \.$showTargetDate
                                                \.$showIcon
                                                \.$showClock
                                            }
                                        }
                                    }
                                } otherwise: {
                                    When(\.$dateScope, .notEqualTo, WidgetDateScope.all) {
                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$manualMediumSelection
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                    \.$showTargetDate
                                                    \.$showIcon
                                                    \.$showClock
                                                }
                                            }
                                        }
                                    } otherwise: {
                                        When(\.$includedTags, .hasAnyValue) {
                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$manualMediumSelection
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                        \.$showTargetDate
                                                        \.$showIcon
                                                        \.$showClock
                                                    }
                                                }
                                            }
                                        } otherwise: {
                                            When(\.$excludedTags, .hasAnyValue) {
                                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$manualMediumSelection
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                            \.$showTargetDate
                                                            \.$showIcon
                                                            \.$showClock
                                                        }
                                                    }
                                                }
                                            } otherwise: {
                                                When(\.$sortOrder, .notEqualTo, WidgetSort.automatic) {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$manualMediumSelection
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                                \.$showTargetDate
                                                                \.$showIcon
                                                                \.$showClock
                                                            }
                                                        }
                                                    }
                                                } otherwise: {
                                                    When(\.$prioritizePinned, .equalTo, false) {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$manualMediumSelection
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$appearance
                                                                    \.$showTargetDate
                                                                    \.$showIcon
                                                                    \.$showClock
                                                                }
                                                            }
                                                        }
                                                    } otherwise: {
                                                        When(\.$skipCount, .notEqualTo, 0) {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                    Summary {
                                                                        \.$contentSource
                                                                        \.$eventID
                                                                        \.$manualMediumSelection
                                                                        \.$showAdvancedFilters
                                                                        \.$dateScope
                                                                        \.$includedTags
                                                                        \.$tagMatch
                                                                        \.$excludedTags
                                                                        \.$sortOrder
                                                                        \.$prioritizePinned
                                                                        \.$skipCount
                                                                        \.$appearance
                                                                    }
                                                                } otherwise: {
                                                                    Summary {
                                                                        \.$contentSource
                                                                        \.$eventID
                                                                        \.$manualMediumSelection
                                                                        \.$showAdvancedFilters
                                                                        \.$dateScope
                                                                        \.$includedTags
                                                                        \.$tagMatch
                                                                        \.$excludedTags
                                                                        \.$sortOrder
                                                                        \.$prioritizePinned
                                                                        \.$skipCount
                                                                        \.$appearance
                                                                        \.$showTargetDate
                                                                        \.$showIcon
                                                                        \.$showClock
                                                                    }
                                                                }
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$manualMediumSelection
                                                                    \.$showAdvancedFilters
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                    Summary {
                                                                        \.$contentSource
                                                                        \.$eventID
                                                                        \.$manualMediumSelection
                                                                        \.$showAdvancedFilters
                                                                        \.$appearance
                                                                    }
                                                                } otherwise: {
                                                                    Summary {
                                                                        \.$contentSource
                                                                        \.$eventID
                                                                        \.$manualMediumSelection
                                                                        \.$showAdvancedFilters
                                                                        \.$appearance
                                                                        \.$showTargetDate
                                                                        \.$showIcon
                                                                        \.$showClock
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } }
                            otherwise: { When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$manualMediumSelection
                                        \.$appearance
                                    }
                                } otherwise: {
                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$manualMediumSelection
                                            \.$appearance
                                            \.$showTargetDate
                                            \.$showIcon
                                            \.$showClock
                                        }
                                    }
                                } }
                        }
                    }
                }
            } otherwise: {
                When(\.$contentSource, .equalTo, WidgetContentSource.smartList) {
                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                        Summary {
                            \.$contentSource
                            \.$smartListID
                            \.$largePageSize
                            \.$appearance
                        }
                    } otherwise: {
                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                            Summary {
                                \.$contentSource
                                \.$smartListID
                                \.$largePageSize
                                \.$appearance
                            }
                        } otherwise: {
                            Summary {
                                \.$contentSource
                                \.$smartListID
                                \.$largePageSize
                                \.$appearance
                                \.$showTargetDate
                                \.$showIcon
                                \.$showClock
                            }
                        }
                    }
                } otherwise: {
                    When(\.$eventID, .equalTo, "automatic") { When(\.$showAdvancedFilters, .equalTo, true) {
                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                Summary {
                                    \.$contentSource
                                    \.$eventID
                                    \.$showAdvancedFilters
                                    \.$dateScope
                                    \.$includedTags
                                    \.$tagMatch
                                    \.$excludedTags
                                    \.$sortOrder
                                    \.$prioritizePinned
                                    \.$skipCount
                                    \.$largePageSize
                                    \.$appearance
                                }
                            } otherwise: {
                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$showAdvancedFilters
                                        \.$dateScope
                                        \.$includedTags
                                        \.$tagMatch
                                        \.$excludedTags
                                        \.$sortOrder
                                        \.$prioritizePinned
                                        \.$skipCount
                                        \.$largePageSize
                                        \.$appearance
                                    }
                                } otherwise: {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$showAdvancedFilters
                                        \.$dateScope
                                        \.$includedTags
                                        \.$tagMatch
                                        \.$excludedTags
                                        \.$sortOrder
                                        \.$prioritizePinned
                                        \.$skipCount
                                        \.$largePageSize
                                        \.$appearance
                                        \.$showTargetDate
                                        \.$showIcon
                                        \.$showClock
                                    }
                                }
                            }
                        } otherwise: {
                            When(\.$dateScope, .notEqualTo, WidgetDateScope.all) {
                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$showAdvancedFilters
                                        \.$dateScope
                                        \.$includedTags
                                        \.$tagMatch
                                        \.$excludedTags
                                        \.$sortOrder
                                        \.$prioritizePinned
                                        \.$skipCount
                                        \.$largePageSize
                                        \.$appearance
                                    }
                                } otherwise: {
                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                            \.$showTargetDate
                                            \.$showIcon
                                            \.$showClock
                                        }
                                    }
                                }
                            } otherwise: {
                                When(\.$includedTags, .hasAnyValue) {
                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                                \.$showTargetDate
                                                \.$showIcon
                                                \.$showClock
                                            }
                                        }
                                    }
                                } otherwise: {
                                    When(\.$excludedTags, .hasAnyValue) {
                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                    \.$showTargetDate
                                                    \.$showIcon
                                                    \.$showClock
                                                }
                                            }
                                        }
                                    } otherwise: {
                                        When(\.$sortOrder, .notEqualTo, WidgetSort.automatic) {
                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                        \.$showTargetDate
                                                        \.$showIcon
                                                        \.$showClock
                                                    }
                                                }
                                            }
                                        } otherwise: {
                                            When(\.$prioritizePinned, .equalTo, false) {
                                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                            \.$showTargetDate
                                                            \.$showIcon
                                                            \.$showClock
                                                        }
                                                    }
                                                }
                                            } otherwise: {
                                                When(\.$skipCount, .notEqualTo, 0) {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$largePageSize
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$largePageSize
                                                                \.$appearance
                                                                \.$showTargetDate
                                                                \.$showIcon
                                                                \.$showClock
                                                            }
                                                        }
                                                    }
                                                } otherwise: {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$largePageSize
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$largePageSize
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$largePageSize
                                                                \.$appearance
                                                                \.$showTargetDate
                                                                \.$showIcon
                                                                \.$showClock
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } }
                    otherwise: {
                        When(\.$eventID, .hasNoValue) { When(\.$showAdvancedFilters, .equalTo, true) {
                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$showAdvancedFilters
                                        \.$dateScope
                                        \.$includedTags
                                        \.$tagMatch
                                        \.$excludedTags
                                        \.$sortOrder
                                        \.$prioritizePinned
                                        \.$skipCount
                                        \.$largePageSize
                                        \.$appearance
                                    }
                                } otherwise: {
                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                            \.$showTargetDate
                                            \.$showIcon
                                            \.$showClock
                                        }
                                    }
                                }
                            } otherwise: {
                                When(\.$dateScope, .notEqualTo, WidgetDateScope.all) {
                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                        Summary {
                                            \.$contentSource
                                            \.$eventID
                                            \.$showAdvancedFilters
                                            \.$dateScope
                                            \.$includedTags
                                            \.$tagMatch
                                            \.$excludedTags
                                            \.$sortOrder
                                            \.$prioritizePinned
                                            \.$skipCount
                                            \.$largePageSize
                                            \.$appearance
                                        }
                                    } otherwise: {
                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                                \.$showTargetDate
                                                \.$showIcon
                                                \.$showClock
                                            }
                                        }
                                    }
                                } otherwise: {
                                    When(\.$includedTags, .hasAnyValue) {
                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                            Summary {
                                                \.$contentSource
                                                \.$eventID
                                                \.$showAdvancedFilters
                                                \.$dateScope
                                                \.$includedTags
                                                \.$tagMatch
                                                \.$excludedTags
                                                \.$sortOrder
                                                \.$prioritizePinned
                                                \.$skipCount
                                                \.$largePageSize
                                                \.$appearance
                                            }
                                        } otherwise: {
                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                    \.$showTargetDate
                                                    \.$showIcon
                                                    \.$showClock
                                                }
                                            }
                                        }
                                    } otherwise: {
                                        When(\.$excludedTags, .hasAnyValue) {
                                            When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                Summary {
                                                    \.$contentSource
                                                    \.$eventID
                                                    \.$showAdvancedFilters
                                                    \.$dateScope
                                                    \.$includedTags
                                                    \.$tagMatch
                                                    \.$excludedTags
                                                    \.$sortOrder
                                                    \.$prioritizePinned
                                                    \.$skipCount
                                                    \.$largePageSize
                                                    \.$appearance
                                                }
                                            } otherwise: {
                                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                        \.$showTargetDate
                                                        \.$showIcon
                                                        \.$showClock
                                                    }
                                                }
                                            }
                                        } otherwise: {
                                            When(\.$sortOrder, .notEqualTo, WidgetSort.automatic) {
                                                When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                    Summary {
                                                        \.$contentSource
                                                        \.$eventID
                                                        \.$showAdvancedFilters
                                                        \.$dateScope
                                                        \.$includedTags
                                                        \.$tagMatch
                                                        \.$excludedTags
                                                        \.$sortOrder
                                                        \.$prioritizePinned
                                                        \.$skipCount
                                                        \.$largePageSize
                                                        \.$appearance
                                                    }
                                                } otherwise: {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                            \.$showTargetDate
                                                            \.$showIcon
                                                            \.$showClock
                                                        }
                                                    }
                                                }
                                            } otherwise: {
                                                When(\.$prioritizePinned, .equalTo, false) {
                                                    When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                        Summary {
                                                            \.$contentSource
                                                            \.$eventID
                                                            \.$showAdvancedFilters
                                                            \.$dateScope
                                                            \.$includedTags
                                                            \.$tagMatch
                                                            \.$excludedTags
                                                            \.$sortOrder
                                                            \.$prioritizePinned
                                                            \.$skipCount
                                                            \.$largePageSize
                                                            \.$appearance
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$largePageSize
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$largePageSize
                                                                \.$appearance
                                                                \.$showTargetDate
                                                                \.$showIcon
                                                                \.$showClock
                                                            }
                                                        }
                                                    }
                                                } otherwise: {
                                                    When(\.$skipCount, .notEqualTo, 0) {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$dateScope
                                                                \.$includedTags
                                                                \.$tagMatch
                                                                \.$excludedTags
                                                                \.$sortOrder
                                                                \.$prioritizePinned
                                                                \.$skipCount
                                                                \.$largePageSize
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$largePageSize
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$showAdvancedFilters
                                                                    \.$dateScope
                                                                    \.$includedTags
                                                                    \.$tagMatch
                                                                    \.$excludedTags
                                                                    \.$sortOrder
                                                                    \.$prioritizePinned
                                                                    \.$skipCount
                                                                    \.$largePageSize
                                                                    \.$appearance
                                                                    \.$showTargetDate
                                                                    \.$showIcon
                                                                    \.$showClock
                                                                }
                                                            }
                                                        }
                                                    } otherwise: {
                                                        When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                                            Summary {
                                                                \.$contentSource
                                                                \.$eventID
                                                                \.$showAdvancedFilters
                                                                \.$largePageSize
                                                                \.$appearance
                                                            }
                                                        } otherwise: {
                                                            When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$showAdvancedFilters
                                                                    \.$largePageSize
                                                                    \.$appearance
                                                                }
                                                            } otherwise: {
                                                                Summary {
                                                                    \.$contentSource
                                                                    \.$eventID
                                                                    \.$showAdvancedFilters
                                                                    \.$largePageSize
                                                                    \.$appearance
                                                                    \.$showTargetDate
                                                                    \.$showIcon
                                                                    \.$showClock
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } }
                        otherwise: { When(\.$appearance, .equalTo, WidgetAppearance.standard) {
                                Summary {
                                    \.$contentSource
                                    \.$eventID
                                    \.$appearance
                                }
                            } otherwise: {
                                When(\.$appearance, .equalTo, WidgetAppearance.compact) {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$appearance
                                    }
                                } otherwise: {
                                    Summary {
                                        \.$contentSource
                                        \.$eventID
                                        \.$appearance
                                        \.$showTargetDate
                                        \.$showIcon
                                        \.$showClock
                                    }
                                }
                            } }
                    }
                }
            }
        }
    }
    init() { eventID = "automatic"; includedTags = []; excludedTags = []; appearance = .standard }
    var pagingID: String? { filter.pageIdentifier(pageSize: min(10, max(5, largePageSize))) }
    var filter: WidgetFilter {
        WidgetFilter(scope: dateScope, includedTags: includedTags, tagMatch: tagMatch, excludedTags: excludedTags,
                     sort: sortOrder, prioritizePinned: prioritizePinned, skip: skipCount)
    }
    var isSmartList: Bool { contentSource == .smartList || eventID?.hasPrefix("smart:") == true }
    var explicitID: String? { eventID == "automatic" || isSmartList ? nil : eventID }
    func makeEntry(events: [CountdownEvent], smartLists: [SmartList], at date: Date) -> DayEntry {
        var entry = DayEntry(date: date, events: events, explicitID: explicitID, error: nil,
            displayOptions: displayOptions, manualSelection: manualSelection, filter: filter,
            pageSize: min(10, max(5, largePageSize)))
        if isSmartList {
            guard let raw = smartListID ?? eventID.flatMap({ $0.hasPrefix("smart:") ? String($0.dropFirst(6)) : nil }), let id = UUID(uuidString: raw),
                  let list = smartLists.first(where: { $0.id == id }) else {
                entry = DayEntry(date: date, events: [], explicitID: nil, error: "智能列表不可用", displayOptions: displayOptions)
                return entry
            }
            entry.smartList = list
            entry.pagingID = list.pageIdentifier(pageSize: entry.pageSize)
        } else { entry.pagingID = pagingID }
        return entry
    }
    var manualSelection: WidgetManualSelection {
        WidgetManualSelection(enabled: manualMediumSelection && !isSmartList, slotIDs: [mediumEvent1ID, mediumEvent2ID, mediumEvent3ID])
    }
    var displayOptions: WidgetDisplayOptions {
        switch appearance {
        case .standard: return WidgetDisplayOptions()
        case .compact: return WidgetDisplayOptions(showIcon: false, showTargetDate: false, showClock: false)
        case .custom, nil: return WidgetDisplayOptions(showIcon: showIcon, showTargetDate: showTargetDate, showClock: showClock)
        }
    }
}

extension WidgetDateScope: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "显示范围" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.all: "全部事件", .upcoming: "未来与今天", .past: "已经过去"]
    }
}
extension WidgetTagMatch: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "标签匹配" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [.all: "包含全部标签", .any: "包含任一标签"] }
}
extension WidgetSort: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "组件排序" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.automatic: "默认顺序", .nearest: "距离最近", .farthest: "距离最远", .dateAscending: "日期从早到晚", .dateDescending: "日期从晚到早", .createdNewest: "最近创建", .title: "按名称"]
    }
}
struct TagOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        CountdownEvent.normalizedTags(try SharedContainer.repository().load().flatMap(\.tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum WidgetAppearance: String, Codable, CaseIterable, AppEnum {
    case standard, compact, custom
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "外观" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.standard: "标准", .compact: "简洁", .custom: "自定"]
    }
}


enum WidgetContentSource: String, Codable, AppEnum {
    case events, smartList
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "内容来源" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [.events: "事件", .smartList: "智能列表"] }
}
struct SmartListOptionsProvider: DynamicOptionsProvider {
    func defaultResult() async -> String? { nil }
    func results() async throws -> IntentItemCollection<String> {
        let items = try SmartListRepository(fileURL: SharedContainer.smartListFileURL()).load().map {
            IntentItem<String>($0.id.uuidString, title: "\($0.name)")
        }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}
