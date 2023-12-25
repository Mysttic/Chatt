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
        private const string DBFileName = "SQLite.db3";

        public const SQLiteOpenFlags Flags =
             SQLiteOpenFlags.ReadWrite |
             SQLiteOpenFlags.Create |
             SQLiteOpenFlags.SharedCache;

        public static string DatabasePath
        {
            get
            {
                return Path
                     .Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), DBFileName);
            }
        }
    }
}
