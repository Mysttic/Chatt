using Chatt.ViewModels;

namespace Chatt.Views;

public partial class DevicesNearbyView : ContentPage
{
	public DevicesNearbyView()
	{
		InitializeComponent();
		BindingContext = new DevicesNearbyViewModel();

	}
}