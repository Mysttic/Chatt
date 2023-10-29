using Chatt.ViewModels;

namespace Chatt.Views;

public partial class UsersNearbyView : ContentPage
{
	public UsersNearbyView()
	{
		InitializeComponent();
		BindingContext = new UsersNearbyViewModel(this);

	}
}