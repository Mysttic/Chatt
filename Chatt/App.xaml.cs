using Chatt.Entities;
using Chatt.Entities.Model;
using Chatt.UI;
using Chatt.Views;

namespace Chatt;

public partial class App : Application
{
	public static BaseRepository<UserModel> UsersRepo { get; private set; }
	public static BaseRepository<SettingsModel> SettingsRepo { get; private set; }
	public static BaseRepository<MessageModel> MessagesRepo { get; private set; }
	public static BaseRepository<ConversationModel> ConversationsRepo { get; private set; }

	public App(
		BaseRepository<UserModel> usersRepo,
        BaseRepository<SettingsModel> settingsRepo,
        BaseRepository<MessageModel> messagesRepo,
        BaseRepository<ConversationModel> conversationsRepo
        )
	{
		InitializeComponent();

		UsersRepo = usersRepo;
		SettingsRepo = settingsRepo;
		MessagesRepo = messagesRepo;
		ConversationsRepo = conversationsRepo;

		MainPage = new AppShell();
	}
}
