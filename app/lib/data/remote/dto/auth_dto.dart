class LoginResponseDto {
  final String accessToken;
  final String tokenType;
  final String userName;
  final String userRole;

  LoginResponseDto({
    required this.accessToken,
    required this.tokenType,
    required this.userName,
    required this.userRole,
  });

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) {
    return LoginResponseDto(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
      userName: json['user_name'],
      userRole: json['user_role'],
    );
  }
}