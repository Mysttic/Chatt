using Chatt.ViewModels;

namespace Chatt.Views;

public partial class SettingsView : ContentPage
{
	public SettingsView()
	{
		InitializeComponent();
		BindingContext = new SettingsViewModel(this);
	}
}