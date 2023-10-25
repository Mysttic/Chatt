using Chatt.grpc;
using Chatt.ViewModels;

namespace Chatt.UI;

public partial class ListOfConversations : ContentPage
{
	public ListOfConversations()
	{
		InitializeComponent();
		BindingContext = new ListOfConversationsViewModel();
	}
}