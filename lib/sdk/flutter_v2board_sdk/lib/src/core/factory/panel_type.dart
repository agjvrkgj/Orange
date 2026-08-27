/// Orange 支持的面板类型。
enum PanelType {
  /// V2Board 面板
  v2board('v2board');

  const PanelType(this.value);

  /// 字符串值
  final String value;

  /// 从字符串创建 PanelType
  static PanelType fromString(String value) {
    return PanelType.values.firstWhere(
      (type) => type.value == value.toLowerCase(),
      orElse: () => throw ArgumentError('Unknown panel type: $value'),
    );
  }

  @override
  String toString() => value;
}
