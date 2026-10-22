import SwiftUI

struct KeyVaultView: View {
    @ObservedObject var vault: KeyVault

    var body: some View {
        ZStack {
            if vault.isUnlocked {
                UnlockedVault(vault: vault)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            } else {
                LockedVault(vault: vault)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LockedVault: View {
    @ObservedObject var vault: KeyVault
    @ViewState private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Button { vault.unlock() } label: {
                Image(systemName: "touchid")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.pink)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulse)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(PressableStyle())
            Text(L("API-ключи защищены"))
                .font(.system(size: 12.5, weight: .semibold))
            Text(vault.authError ?? L("Нажмите и подтвердите Touch ID или паролем Mac"))
                .font(.system(size: 11))
                .foregroundStyle(vault.authError == nil ? .white.opacity(0.45) : .red.opacity(0.85))
        }
        .onAppear {
            pulse = true
            vault.unlock()
        }
    }
}

private struct UnlockedVault: View {
    @ObservedObject var vault: KeyVault
    @ViewState private var adding = false
    @ViewState private var name = ""
    @ViewState private var value = ""
    @ViewState private var copiedID: UUID?
    @ViewState private var revealedID: UUID?

    var body: some View {
        VStack(spacing: 6) {
            if adding {
                addForm.transition(.move(edge: .top).combined(with: .opacity))
            }
            if vault.keys.isEmpty && !adding {
                VStack(spacing: 6) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(L("Ключей пока нет"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.45))
                    addButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(vault.keys) { key in
                            row(key).transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                if !adding {
                    HStack {
                        Label(L("Разблокировано"), systemImage: "lock.open.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green.opacity(0.8))
                        Spacer()
                        Button(L("Заблокировать")) { vault.lock() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        addButton
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { adding = true }
        } label: {
            Label(L("Добавить"), systemImage: "plus")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
    }

    private var addForm: some View {
        HStack(spacing: 6) {
            TextField(L("Название"), text: $name)
                .frame(width: 120)
            SecureField(L("Ключ"), text: $value)
            Button {
                value = NSPasteboard.general.string(forType: .string) ?? value
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
            .help(L("Вставить из буфера обмена"))
            Button(L("Сохранить")) {
                vault.add(name: name, value: value)
                name = ""; value = ""
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { adding = false }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(value.isEmpty ? .white.opacity(0.3) : .green)
            .disabled(value.isEmpty)
            Button {
                name = ""; value = ""
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { adding = false }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
        }
        .textFieldStyle(.plain)
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
    }

    private func row(_ key: APIKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.yellow.opacity(0.14)))
            Text(key.name)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            Text(revealedID == key.id ? key.value : key.masked)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { revealedID = revealedID == key.id ? nil : key.id }
            } label: {
                Image(systemName: revealedID == key.id ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.55))
            Button {
                vault.copy(key)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { copiedID = key.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.25)) { if copiedID == key.id { copiedID = nil } }
                }
            } label: {
                Image(systemName: copiedID == key.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedID == key.id ? .green : .white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(L("Скопировать ключ"))
            Button { vault.delete(key) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.35))
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
    }
}
