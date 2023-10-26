using Chatt.ViewModels;

namespace Chatt.Views;

public partial class ConversationView : ContentPage
{
	public ConversationView()
	{
		InitializeComponent();
		BindingContext = new ConversationViewModel();
	}
}