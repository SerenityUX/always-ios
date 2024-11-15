//
//  AuthViews.swift
//  hack-time
//
//  Created by Thomas Stubblefield on 10/29/24.
//

import SwiftUI

struct OnboardingView: View {
    @State private var showLogin = false
    @State private var showSignup = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#FEE353")
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Image("alwaysLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 64)
                        .padding(.vertical, 32)

                    Spacer()
                    VStack(spacing: 12){
                        Button(action: {
                            showLogin = true
                        }, label: {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: "#492802"))
                                .foregroundColor(Color(hex: "#FEE353"))
                                .cornerRadius(16)
                                .font(.system(size: 18))
                                .fontWeight(.medium)
                        })
                        .padding(.horizontal, 16)
                        
                        Button(action: {
                            showSignup = true
                        }, label: {
                            Text("Signup")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: "#FEE353"))
                                .foregroundColor(Color(hex: "#492802"))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(hex: "#492802"), lineWidth: 2)
                                )
                                .font(.system(size: 18))
                                .fontWeight(.medium)
                        })
                        .padding(.horizontal, 16)
                    }
                }
                .navigationDestination(isPresented: $showLogin) {
                    LoginView()
                }
                .navigationDestination(isPresented: $showSignup) {
                    SignupView()
                }
            }
        }
    }
}

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showForgotPassword = false
    
    @FocusState private var focusedField: LoginField?
    
    enum LoginField {
        case email
        case password
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Welcome Back")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .foregroundColor(.gray)
                        HStack {
                            if showPassword {
                                TextField("Enter your password", text: $password)
                                    .textContentType(.password)
                                    .submitLabel(.done)
                            } else {
                                SecureField("Enter your password", text: $password)
                                    .textContentType(.password)
                                    .submitLabel(.done)
                            }
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            handleLogin()
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: handleLogin) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Login")
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Button(action: {
                    showForgotPassword = true
                }) {
                    Text("Forgot Password?")
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("By logging in, you agree to our")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Link("Terms and Conditions", destination: URL(string: "https://serenidad.click/hacktime/privacy-toc")!)
                        .font(.footnote)
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .email
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    private func handleLogin() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let token = try await authManager.login(email: email, password: password)
                await MainActor.run {
                    UserDefaults.standard.set(token, forKey: "authToken")
                    authManager.isAuthenticated = true
                    dismiss()
                }
            } catch AuthError.invalidCredentials {
                errorMessage = "Invalid email or password"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}

struct SignupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @FocusState private var focusedField: SignupField?
    
    enum SignupField {
        case name
        case email
        case password
        case confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Create Account")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .foregroundColor(.gray)
                    TextField("Enter your name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .email
                        }
                }
                .padding(.horizontal, 24)
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .foregroundColor(.gray)
                        HStack {
                            if showPassword {
                                TextField("Enter your password", text: $password)
                                    .textContentType(.password)
                            } else {
                                SecureField("Enter your password", text: $password)
                                    .textContentType(.password)
                            }
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .foregroundColor(.gray)
                        HStack {
                            if showConfirmPassword {
                                TextField("Confirm your password", text: $confirmPassword)
                                    .textContentType(.password)
                            } else {
                                SecureField("Confirm your password", text: $confirmPassword)
                                    .textContentType(.password)
                            }
                            
                            Button(action: {
                                showConfirmPassword.toggle()
                            }) {
                                Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.join)
                        .onSubmit {
                            handleSignup()
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: handleSignup) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign Up")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("By signing up, you agree to our")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Link("Terms and Conditions", destination: URL(string: "https://serenidad.click/hacktime/privacy-toc")!)
                        .font(.footnote)
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .email
            }
        }
    }
    
    private func handleSignup() {
        guard !email.isEmpty && !password.isEmpty && !name.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let token = try await authManager.signup(email: email, password: password, name: name)
                await MainActor.run {
                    UserDefaults.standard.set(token, forKey: "authToken")
                    authManager.isAuthenticated = true
                    dismiss()
                }
            } catch AuthError.emailInUse {
                errorMessage = "Email is already in use"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    @State private var email: String = ""
    @State private var oneTimeCode: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var codeSent = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email
        case code
        case password
        case confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(codeSent ? "Reset Password" : "Forgot Password")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                if !codeSent {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .foregroundColor(.gray)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Code")
                                .foregroundColor(.gray)
                            TextField("Enter the code sent to your email", text: $oneTimeCode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .code)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                    TextField("Enter new password", text: $newPassword)
                                } else {
                                    SecureField("Enter new password", text: $newPassword)
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .password)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .confirmPassword
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .foregroundColor(.gray)
                            HStack {
                                if showPassword {
                                    TextField("Confirm new password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm new password", text: $confirmPassword)
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($focusedField, equals: .confirmPassword)
                            .submitLabel(.done)
                            .onSubmit {
                                handlePasswordReset()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: codeSent ? handlePasswordReset : handleCodeRequest) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(codeSent ? "Reset Password" : "Send Code")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .disabled(isLoading)
                
                Spacer()
            }
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            })
        }
        .onAppear {
            focusedField = .email
        }
    }
    
    private func handleCodeRequest() {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.requestPasswordReset(email: email)
                await MainActor.run {
                    codeSent = true
                    focusedField = .code
                }
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
    
    private func handlePasswordReset() {
        guard !oneTimeCode.isEmpty else {
            errorMessage = "Please enter the code"
            return
        }
        
        guard !newPassword.isEmpty else {
            errorMessage = "Please enter a new password"
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.changePassword(email: email, oneTimeCode: oneTimeCode, newPassword: newPassword)
                await MainActor.run {
                    dismiss()
                }
            } catch AuthError.invalidCode {
                errorMessage = "Invalid code"
            } catch {
                errorMessage = "An error occurred. Please try again."
            }
            isLoading = false
        }
    }
}
