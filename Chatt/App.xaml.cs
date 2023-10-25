using Chatt.UI;
using Chatt.Views;

namespace Chatt;

public partial class App : Application
{
	public App()
	{
		InitializeComponent();

		MainPage = new AppShell();
	}
}
