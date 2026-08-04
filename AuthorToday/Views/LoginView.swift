import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.22, blue: 0.20),
                    Color(red: 0.08, green: 0.12, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // subtle grain-like overlay via pattern of circles
            GeometryReader { geo in
                Canvas { context, size in
                    for i in 0..<40 {
                        let x = CGFloat((i * 47) % Int(size.width))
                        let y = CGFloat((i * 89) % Int(size.height))
                        let r = CGFloat(20 + (i % 5) * 8)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                            with: .color(.white.opacity(0.03))
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Author.Today")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)

                    Text("Читайте онлайн и офлайн.\nВаша библиотека всегда под рукой.")
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer(minLength: 36)

                VStack(spacing: 14) {
                    TextField("Email или логин", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .padding()
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .padding()
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)

                    if let error = auth.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
                        }
                    } label: {
                        if auth.isBusy {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("Войти")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(AppTheme.mossSoft)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(email.isEmpty || password.isEmpty || auth.isBusy)
                    .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
                }
                .padding(22)
                .background(.ultraThinMaterial.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 22)

                Spacer()

                Text("Вход через API author.today")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 24)
            }
        }
        .onSubmit {
            if focused == .email {
                focused = .password
            } else {
                Task {
                    await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
                }
            }
        }
    }
}
