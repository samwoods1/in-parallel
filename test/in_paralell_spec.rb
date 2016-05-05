require 'rspec'
require_relative('../lib/in_parallel')

TMP_FILE = '/tmp/test_file.txt'

# Helper functions for the unit tests
def method_with_param(param)
  puts "foo"
  puts "bar + #{param} \n"
  sleep 3
  return "bar + #{param}"
end

def method_without_param
  ret_val = {:foo => "bar"}
  puts ret_val
  sleep 2
  return ret_val
end

def create_file_with_delay(file_path)
  sleep 2
  File.open(file_path, 'w') { |f| f.write('contents')}
  return true
end

#Tests
describe '.run_in_parallel' do
  it 'should run in parallel' do
    start_time = Time.now

    InParallel.run_in_parallel{
      @result_from_test = method_with_param('blah')
      @result_2 = method_without_param
    }
    # time should be less than combined delay in the 2 methods
    expect(Time.now - start_time).to be < 5
    # return values for instance variables should be set correctly
    expect(@result_from_test).to eq 'bar + blah'
    # should be able to return objects (not just strings)
    expect(@result_2).to eq({:foo => "bar"})
  end

end

describe '.run_in_background' do
  before do
    File.delete(TMP_FILE) if File.exists?(TMP_FILE)
  end

  it 'should run in the background' do
    InParallel.run_in_background{
      @result = create_file_with_delay(TMP_FILE)
    }

    # Should not exist immediately upon block completion
    expect(File.exists? TMP_FILE).to eq false
    sleep(3)
    # Should exist once the delay in create_file_with_delay is done
    expect(File.exists? TMP_FILE).to eq true
  end

  it 'should allow you to get results if ignore_results is false' do
    @block_result = InParallel.run_in_background(false){
      @result = create_file_with_delay(TMP_FILE)
    }
    InParallel.get_background_results
    # We should get the correct value assigned for the method result
    expect(@result).to eq true
  end

end

describe '.each_in_parallel' do
  it 'should run each iteration in parallel' do
    start_time = Time.now
    items = ['foo', 'bar', 'baz'].each_in_parallel {|item|
      sleep 1
      puts item
      item
    }
    # return values should be an array of the returned items in the last line of the block
    expect(items <=> ['foo', 'bar', 'baz']).to eq 0
    # time should be less than combined delay in the 3 block calls
    expect(expect(Time.now - start_time).to be < 3)
  end
end
