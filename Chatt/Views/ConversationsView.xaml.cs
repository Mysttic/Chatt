using Chatt.Grpc;
using Chatt.ViewModels;

namespace Chatt.UI;

public partial class ConversationsView : ContentPage
{
	public ConversationsView()
	{
		InitializeComponent();
		BindingContext = new ConversationsViewModel(this);
	}
}