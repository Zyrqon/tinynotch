import SwiftUI

/// Центр уведомлений: Gmail и уведомления приложений, сгруппированные по источнику.
struct NotificationsView: View {
    @ObservedObject var gmail: GmailClient
    @ObservedObject var system: SystemNotificationsReader
    @ViewState private var expanded: String?

    private struct AppGroup: Identifiable {
        var id: String { bundleID }
        var bundleID: String
        var items: [AppNotification]
    }

    private var appGroups: [AppGroup] {
        Dictionary(grouping: system.notifications, by: \.bundleID)
            .map { AppGroup(bundleID: $0.key, items: Array($0.value.sorted { $0.date > $1.date }.prefix(20))) }
            .sorted { ($0.items.first?.date ?? .distantPast) > ($1.items.first?.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                gmailSection
                if system.needsFullDiskAccess {
                    accessRow
                } else if let error = system.readError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                if !appGroups.isEmpty {
                    HStack {
                        Text(L("Приложения"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Button(L("Очистить всё")) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { system.dismissAll() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
                ForEach(appGroups) { group in
                    appSection(group)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
                if !system.needsFullDiskAccess && appGroups.isEmpty && gmail.mails.isEmpty && gmail.isConnected {
                    Text(L("Новых уведомлений нет"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 20)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            expanded = expanded == id ? nil : id
        }
    }

    // MARK: - Gmail

    private var gmailSection: some View {
        VStack(spacing: 2) {
            GroupHeader(icon: .store("com.google.Gmail", fallback: "envelope.fill"),
                        title: "Gmail",
                        subtitle: gmail.account ?? L("Не подключено"),
                        count: gmail.mails.count,
                        latest: gmail.mails.first?.date,
                        isExpanded: expanded == "gmail") { toggle("gmail") }
            if expanded == "gmail" {
                Group {
                    if gmail.isConnected && !gmail.needsPassword {
                        VStack(spacing: 2) {
                            ForEach(gmail.mails) { mail in
                                MailRow(mail: mail) { gmail.open(mail) }
                            }
                            if gmail.mails.isEmpty {
                                Text(L("Непрочитанных писем нет"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.vertical, 6)
                            }
                            HStack(spacing: 14) {
                                Button(L("Открыть Gmail")) { gmail.openInbox() }
                                Button(L("Обновить")) { gmail.refresh() }
                                Spacer()
                                Button(L("Отключить")) { gmail.disconnect() }
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                        }
                    } else {
                        GmailConnectForm(gmail: gmail)
                    }
                }
                .padding(.leading, 30)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Приложения

    private func appSection(_ group: AppGroup) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                GroupHeader(icon: .app(group.bundleID), title: appName(group.bundleID),
                            subtitle: group.items.first.map { $0.title } ?? "",
                            count: group.items.count, latest: group.items.first?.date,
                            isExpanded: expanded == group.id) { toggle(group.id) }
                DismissButton(help: L("Удалить все уведомления %@", "\(appName(group.bundleID))")) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        system.dismissAll(bundleID: group.bundleID)
                    }
                }
            }
            if expanded == group.id {
                VStack(spacing: 2) {
                    ForEach(group.items) { item in
                        AppNotificationRow(item: item) { openApp(group.bundleID) } onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { system.dismiss(item) }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.leading, 30)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var accessRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Telegram, WhatsApp и другие приложения"))
                    .font(.system(size: 11.5, weight: .semibold))
                Text(L("Нужен «Полный доступ к диску». Уже выдан? Удалите Notchly из списка и добавьте снова"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button(L("Открыть настройки")) { system.openFullDiskAccessSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04)))
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

// MARK: - Строки

private enum GroupIcon {
    case app(String)
    case store(String, fallback: String)
}

private struct GroupHeader: View {
    var icon: GroupIcon
    var title: String
    var subtitle: String
    var count: Int
    var latest: Date?
    var isExpanded: Bool
    var action: () -> Void
    @ViewState private var hovering = false
    @ViewState private var remoteIcon: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                iconView.frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                if let latest {
                    Text(shortTimestamp(latest))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isExpanded ? 0.1 : (hovering ? 0.07 : 0.03))))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.badge").font(.system(size: 14))
            }
        case .store(let bundleID, let fallback):
            Group {
                if let remoteIcon {
                    Image(nsImage: remoteIcon).resizable()
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: fallback).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
            .onAppear {
                RemoteImages.appIcon(bundleID: bundleID) { remoteIcon = $0 }
            }
        }
    }
}

private struct MailRow: View {
    var mail: MailItem
    var action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(mail.senderName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        if !mail.senderEmail.isEmpty && mail.senderEmail != mail.senderName {
                            Text(mail.senderEmail)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .lineLimit(1)
                    Text(mail.subject)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(shortTimestamp(mail.date))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Открыть письмо в Gmail"))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

private struct AppNotificationRow: View {
    var item: AppNotification
    var action: () -> Void
    var onDismiss: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.subtitle.isEmpty ? item.title : "\(item.title) · \(item.subtitle)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                ZStack(alignment: .trailing) {
                    Text(shortTimestamp(item.date))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                        .opacity(hovering ? 0 : 1)
                    if hovering {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("Удалить уведомление"))
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

private struct GmailConnectForm: View {
    @ObservedObject var gmail: GmailClient
    @ViewState private var email = ""
    @ViewState private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("you@gmail.com", text: $email)
                    .frame(width: 170)
                    .onAppear { if email.isEmpty, let account = gmail.account { email = account } }
                SecureField(L("Пароль приложения"), text: $password)
                Button {
                    gmail.connect(email: email, appPassword: password)
                } label: {
                    if gmail.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("Подключить")).font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(email.isEmpty || password.isEmpty ? .white.opacity(0.3) : .green)
                .disabled(email.isEmpty || password.isEmpty || gmail.isLoading)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))

            HStack(spacing: 4) {
                if let error = gmail.error {
                    Text(error).foregroundStyle(.red.opacity(0.85))
                } else {
                    Text(L("Нужен пароль приложения Google, не основной пароль."))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Button(L("Создать →")) {
                    NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/apppasswords")!)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .font(.system(size: 10.5))
            .padding(.leading, 4)
        }
        .padding(.vertical, 2)
    }
}
