// 操作类型枚举
enum OperType {
  login('LOGIN'),
  startLearn('START_LEARN'),
  daka('DAKA'),
  throwDice('THROW_DICE');

  final String value;
  const OperType(this.value);

  static OperType fromString(String value) {
    return OperType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OperType.login,
    );
  }
}
