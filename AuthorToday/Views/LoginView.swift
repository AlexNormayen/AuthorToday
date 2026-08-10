import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password, code }

    var body: some View {
        ZStack {
            // Dim the living atmosphere so white login copy stays readable on any theme.
            Color.black.opacity(appearance.themePreset.prefersDark ? 0.22 : 0.42)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Читальня")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)

                    Text(auth.awaitingTwoFactor
                         ? "Введите код из письма — Author.Today\nпросит подтвердить это устройство."
                         : "Клиент Author.Today (неофициальный).\nЧитайте онлайн и офлайн.")
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer(minLength: 36)

                Group {
                    if auth.awaitingTwoFactor {
                        twoFactorForm
                    } else {
                        credentialsForm
                    }
                }
                .padding(22)
                .background(.ultraThinMaterial.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 22)

                Spacer()

                VStack(spacing: 6) {
                    Text("Это приложение не является официальным продуктом Author.Today и не связано с порталом.")
                        .font(.caption.weight(.medium))
                    Text("Книги и оплата — только на author.today. Author.Today не отвечает за работу Читальни.")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if email.isEmpty, let remembered = auth.rememberedLogin {
                email = remembered
            }
        }
        .onChange(of: auth.awaitingTwoFactor) { _, waiting in
            if waiting {
                confirmationCode = ""
                focused = .code
            } else {
                focused = .email
            }
        }
        .onSubmit { handleSubmit() }
    }

    private var credentialsForm: some View {
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

            primaryButton(
                title: "Войти",
                disabled: email.isEmpty || password.isEmpty || auth.isBusy
            ) {
                Task {
                    await auth.login(
                        email: email.trimmingCharacters(in: .whitespaces),
                        password: password
                    )
                }
            }
        }
    }

    private var twoFactorForm: some View {
        VStack(spacing: 14) {
            Text("Код из письма")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Код подтверждения", text: $confirmationCode)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .code)
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

            primaryButton(
                title: "Войти",
                disabled: confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || auth.isBusy
            ) {
                Task { await auth.submitTwoFactorCode(confirmationCode) }
            }

            HStack(spacing: 16) {
                Button {
                    auth.cancelTwoFactor()
                    confirmationCode = ""
                } label: {
                    Text("Назад")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.9))
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(auth.isBusy)

                Button {
                    Task { await auth.resendTwoFactorCode() }
                } label: {
                    Text("Отправить снова")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.9))
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(auth.isBusy)
            }
        }
    }

    private func primaryButton(
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if auth.isBusy {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .background(appearance.accent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(disabled)
        .opacity(disabled && !auth.isBusy ? 0.5 : 1)
    }

    private func handleSubmit() {
        if auth.awaitingTwoFactor {
            Task { await auth.submitTwoFactorCode(confirmationCode) }
            return
        }
        if focused == .email {
            focused = .password
        } else {
            Task {
                await auth.login(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
        }
    }
}
