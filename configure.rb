require 'config/path'
require 'config/config'
require 'config/opts'

#Todo:
#  - find/download/compile LAPACK
#  - find ATLAS
#  - write out stuff to .config
# EOS

opts = Opts.new(ARGV)

config = Config.new

def dir(s)
  case $os_name
  when 'Linux'
    s
  when 'WinXP'
    %x(cygpath #{s}).chomp
  else
    raise ConfigError.new, "The OS #{$os_name} is currently unsupported!"
  end
end

begin
  ######################################################################
  config.msg('checking for java, javac') do 
    config.check_cmd('java', 'javac')
    %x(javac config/PrintProperty.java)
    nil
  end

  ######################################################################
  config.msg('locating the Java Development Kit') do
    $java_home = File.dirname(%x(java -cp config PrintProperty java.home))
    config.check_files $java_home, ['include', 'jni.h'] do
      config['JAVA_HOME'] = $java_home
    end
  end

  ######################################################################
  config.msg('Determining operating system') do
    $os_name = %x(java -cp config PrintProperty os.name).chomp
    if $os_name == 'WinXP'
      config.check_cmd 'cygpath'
    end
    $os_name
  end
  
  ######################################################################
  config.msg('deciding whether to use g77 or gfortran') do
    g77 = where('g77')
    gfortran = where('gfortran')
    if g77
      config['LD'] = 'g77'
    elsif gfortran
      config['LD'] = 'gfortran'
    else
      config.fail <<EOS
Either g77 or gfortran have to be installed to compile against the
fortran libraries.
EOS
    end
  end
  
  ######################################################################
  config.msg('Setting up gcc and flags') do
    config.check_cmd('gcc', 'make', 'ld')
    case $os_name
    when 'Linux'
      config << <<EOS
CC = gcc
CFLAGS = -fPIC -ggdb
INCDIRS += -Iinclude -I#{$java_home}/include -I#{$java_home}/include/linux
SO = so
LIB = lib
RUBY=ruby
LDFLAGS += -shared
EOS
      if opts.defined? :lapack_build
        config << <<EOS
LOADLIBES=-llapack-fortran -lblas-fortran
EOS
      else # the default - atlas build
        config << <<EOS
LOADLIBES=-llapack -lf77blas -latlas -llapack-fortran -lblas-fortran
EOS
      end
        
    when 'WinXP'
      config.check_cmd('cygpath')
      config << <<EOS
CC = gcc
CFLAGS = -ggdb -D__int64='long long'
INCDIRS += -I"#{dir $java_home}/include" -I"#{dir $java_home}/include/win32" -Iinclude
LDFLAGS += -mno-cygwin -shared -Wl,--add-stdcall-alias
SO = dll
LIB = ""
RUBY = 
EOS
    else
      config.fail "Sorry, the OS #{$os_name} is currently not supported"
    end
  end

  ######################################################################
  config.msg('locating lapack sources') do
    $lapack_home = opts.get :lapack, './lapack-lite-3.1.1'
    begin
      config.check_files($lapack_home, 
                         ['BLAS', 'SRC', 'dgemm.f'], 
                         ['SRC', 'dsyev.f']) do
        config['LAPACK_HOME'] = $lapack_home
        config['LDFLAGS'] <<= '-L' + dir($lapack_home)
      end
    rescue ConfigError => e
      raise ConfigError, <<EOS
Couldn\'t locate sources for LAPACK and BLAS. Sources for lapack can be
found at http://www.netlib.org/lapack/lapack-lite-3.1.1.tgz
EOS
    end
    $lapack_home
  end

  ######################################################################
  LAPACK_LIBS = [['libblas-fortran.a'], ['liblapack-fortran.a']]
  config.msg('checking for LAPACK and BLAS libraries') do
    begin
      config.check_files($lapack_home, *LAPACK_LIBS)
    rescue ConfigError => e
      config.msg("trying to compile LAPACK and BLAS libraries") do
        out = %x(bash config/compile_lapack #{$lapack_home})
        open('configure.compile_log', 'w') {|o| o.print out}
        config.check_files($lapack_home, *LAPACK_LIBS)
      end
    end
  end
  
  ######################################################################
  unless opts.defined? :lapack_build
    config.msg('locating atlas libraries') do
      LIBPATH = opts.get :libpath, %w(/usr/lib /lib /usr/lib/sse2)
      ATLASLIBS = %w(libf77blas.so libatlas.so liblapack.so libblas.so liblapack.so)
      $atlas_libs = collect_paths(ATLASLIBS, LIBPATH)
      unless $atlas_libs
        config.fail <<EOS
Couldn\'t locate the ATLAS libraries #{ATLASLIBS.join(', ')}
EOS
      else
        config['LDFLAGS'] <<= $atlas_libs.map {|p| '-L' + dir(p)}.join(' ')
      end
      nil
    end
  end
  
  ######################################################################
  # dumping results
  puts
  puts 'Configuration succesfull, writing out results to configure.out'
  open('configure.out', 'w') {|f| config.dump f}

rescue ConfigError => e
  puts 
  puts "Configuration failed!"
  puts
  puts "Reason: #{e.message}"
end
