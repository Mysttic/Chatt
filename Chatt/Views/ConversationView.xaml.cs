using Chatt.Entities.Model;
using Chatt.ViewModels;

namespace Chatt.Views;

public partial class ConversationView : ContentPage
{
	public ConversationView(ConversationModel conversationModel)
	{
		InitializeComponent();
		BindingContext = new ConversationViewModel(this, conversationModel);
	}
}