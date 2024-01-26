using SQLite;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities
{
    internal static class Constants
    {
        //Remember when modify to change that in file Chatt.DataContext/Constants.cs
        private const string DBFileName = "chatt.db";

        public const SQLiteOpenFlags Flags =
             SQLiteOpenFlags.ReadWrite |
             SQLiteOpenFlags.Create |
             SQLiteOpenFlags.SharedCache;

        public static string DatabasePath
        {
            get
            {
                var folder = Environment.SpecialFolder.LocalApplicationData;
                var path = Environment.GetFolderPath(folder);
                path = Path.Join(path, "Chatt");
                if (!Directory.Exists(path))
                    Directory.CreateDirectory(path);
                return Path.Join(path, DBFileName);
            }
        }
    }
}
