import Foundation

// In-app UI localization. English is the default: keys are the English
// strings themselves, and any key missing from the Chinese table falls
// back to the key unchanged. Selected via the "appLanguage" AppStorage
// key ("en" / "zh") in Settings.
enum L10n {
    static func text(_ key: String, _ language: String) -> String {
        guard language == "zh" else { return key }
        return zh[key] ?? key
    }

    private static let zh: [String: String] = [
        "Start": "开始",
        "Stop": "停止",
        "Files": "文件",
        "Setting": "设置",
        "Current Position": "当前位置",
        "Speed": "速度",
        "Altitude": "海拔",
        "Distance": "距离",
        "POIs": "兴趣点",
        "Latitude": "纬度",
        "Longitude": "经度",
        "Excellent": "极好",
        "Good": "良好",
        "Fair": "一般",
        "Poor": "较差",
        "Very Poor": "很差",
        "GPS Status": "GPS 状态",
        "Precise Location is off — accuracy is limited to ~1–2 km.": "精确位置已关闭，定位精度限制在约 1–2 公里。",
        "Enable Precise Location": "开启精确位置",
        "Signal Quality": "信号质量",
        "Accuracy": "精度",
        "Signal Level": "信号强度",
        "Detailed Metadata": "详细信息",
        "Vertical Accuracy": "垂直精度",
        "Course": "航向",
        "Timestamp": "时间戳",
        "Source": "来源",
        "Simulated": "模拟",
        "GPS/Hardware": "GPS/硬件",
        "No GPS data available": "暂无 GPS 数据",
        "Done": "完成",
        "Tracks": "轨迹",
        "No Tracks": "暂无轨迹",
        "Tracks are saved here automatically when you stop recording.": "停止录制后，轨迹会自动保存在这里。",
        "Share": "分享",
        "Delete": "删除",
        "Merge": "合并",
        "Settings": "设置",
        "Map": "地图",
        "Map Type": "地图类型",
        "Standard": "标准",
        "Satellite": "卫星",
        "Units": "单位",
        "Imperial (mi, mph)": "英制（英里、英里/小时）",
        "Screen": "屏幕",
        "Keep Screen On": "屏幕常亮",
        "Language": "语言",
    ]
}
