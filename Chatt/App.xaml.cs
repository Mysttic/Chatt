using Chatt.Entities;
using Chatt.Entities.Model;
using Chatt.Entities.Repositories;
using Chatt.Grpc;
using Chatt.Network;
using Chatt.UI;
using Chatt.Views;

namespace Chatt;

public partial class App : Application
{
    public static GrpcFactor GrpcFactor { get; private set; }
	public static BaseRepository<UserModel> UsersRepo { get; private set; }
	public static SettingsRepository SettingsRepo { get; private set; }
	public static BaseRepository<MessageModel> MessagesRepo { get; private set; }
	public static BaseRepository<ConversationModel> ConversationsRepo { get; private set; }

	public App(
		BaseRepository<UserModel> usersRepo,
        SettingsRepository settingsRepo,
        BaseRepository<MessageModel> messagesRepo,
        BaseRepository<ConversationModel> conversationsRepo
        )
	{
		InitializeComponent();

		UsersRepo = usersRepo;
		SettingsRepo = settingsRepo;
		MessagesRepo = messagesRepo;
		ConversationsRepo = conversationsRepo;

        SettingsModel settings = SettingsRepo.GetSettings();
        if (settings == null)        
            throw new Exception("Settings not found");
        if (settings.ActivePort == 0 || settings.ActivePort != settings.CustomPort)
        {
            FirewallRuleManager.NewFirewallRule(settings.CustomPort, settings.ActivePort);
            settings.ActivePort = settings.CustomPort;
            SettingsRepo.SaveItem(settings);
        }

        GrpcFactor = GrpcFactor.Instance(settings.ActivePort);

        MainPage = new AppShell();
	}

}
