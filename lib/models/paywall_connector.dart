class PaywallConnector {
  const PaywallConnector({this.colorId, this.thickness});

  final String? colorId;
  final String?
      thickness; // stored as string in payload, parse to double when using

  factory PaywallConnector.fromJson(Map<String, dynamic> json) =>
      PaywallConnector(
        colorId: json['colorId'] as String?,
        thickness: json['thickness']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        if (colorId != null) 'colorId': colorId,
        if (thickness != null) 'thickness': thickness,
      };
}
