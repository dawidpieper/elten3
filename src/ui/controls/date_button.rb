# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
class DateButton < Button
  attr_reader :year, :month, :day, :hour, :min, :sec
  def initialize(label, years_range=1900..2100, include_hour: false)
    @year, @month, @day, @hour, @min, @sec = 0, 0, 0, 0, 0, 0
    @dlabel=label
genlabel
super(@label)
    @minyear=years_range.begin
    @maxyear=years_range.end
    @includehour=include_hour
    @years=(@minyear..@maxyear).to_a.map{|y|y.to_s}
    @months = [p_("EAPI_Form", "January"), p_("EAPI_Form", "February"), p_("EAPI_Form", "March"), p_("EAPI_Form", "April"), p_("EAPI_Form", "May"), p_("EAPI_Form", "June"), p_("EAPI_Form", "July"), p_("EAPI_Form", "August"), p_("EAPI_Form", "September"), p_("EAPI_Form", "October"), p_("EAPI_Form", "November"), p_("EAPI_Form", "December")]
    @days=(1..31).to_a.map{|d|d.to_s}
    @hours=(0..23).to_a.map{|h|sprintf("%02d",h)}
    @mins=(0..59).to_a.map{|m|sprintf("%02d",m)}
    @secs=(0..59).to_a.map{|s|sprintf("%02d",s)}
    @form = Form.new([
    @sel_year = ListBox.new([p_("EAPI_Form", "Not selected")]+@years, header: p_("EAPI_Form", "Year")),
    @sel_month = ListBox.new([p_("EAPI_Form", "Not selected")], header: p_("EAPI_Form", "Month")),
    @sel_day = ListBox.new([p_("EAPI_Form", "Not selected")], header: p_("EAPI_Form", "Day")),
@sel_hour = ListBox.new([p_("EAPI_Form", "Not selected")], header: p_("EAPI_Form", "Hour")),
@sel_min = ListBox.new([p_("EAPI_Form", "Not selected")], header: p_("EAPI_Form", "Minute")),
@sel_sec = ListBox.new([p_("EAPI_Form", "Not selected")], header: p_("EAPI_Form", "Second")),
    @btn_select = Button.new(p_("EAPI_Form", "Ready")),
    @btn_cancel = Button.new(_("Cancel"))
    ], index: 0, silent: false, quiet: true)
    if @includehour==false
      @form.hide(@sel_hour)
      @form.hide(@sel_min)
      @form.hide(@sel_sec)
      end
    @form.cancel_button = @btn_cancel
    @form.accept_button = @btn_select
    @btn_cancel.on(:press) {@form.resume}
    @btn_select.on(:press) {
   if @sel_year.index==0
     @year=0
   else
     @year=@sel_year.index+@minyear-1
   end
   @month=@sel_month.index
   @day=@sel_day.index
   if @year==0 || @month==0 || @day==0
     @year=0
     @month=0
     @day=0
   end
   if @includehour==true
     @hour=@sel_hour.index-1
     @min=@sel_min.index-1
     @sec=@sel_sec.index-1
     if @hour==-1 || @min==-1 || @sec==-1
       @year=0
     @month=0
     @day=0
     @hour=-1
     @min=-1
     @sec=-1
       end
     end
   @form.resume
    }
    @sel_year.on(:move) {
    if @sel_year.index==0
      @sel_month.options=[p_("EAPI_Form", "Not selected")]
    else
      @sel_month.options=[p_("EAPI_Form", "Not selected")]+@months
      end
        @sel_month.index-=1 while @sel_month.index>=@sel_month.options.size
        @sel_month.trigger(:move, @sel_month.index)
    }
    @sel_month.on(:move) {
    if @sel_month.index==0
      @sel_day.options=[p_("EAPI_Form", "Not selected")]
    else
      days=31
      days=30 if [4, 6, 9, 11].include?(@sel_month.index)
      if @sel_month.index==2
        if (@sel_year.index+@minyear-1)%4==0 && (((@minyear+@sel_year.index-1)%100)!=0 || ((@minyear+@sel_year.index-1)%400)==0)
          days=29
        else
          days=28
        end
        end
        @sel_day.options = [p_("EAPI_Form", "Not selected")]+@days[0...days]
      end
              @sel_day.index-=1 while @sel_day.index>=@sel_day.options.size
              @sel_day.trigger(:move, @sel_day.index)
    }
    @sel_day.on(:move) {
    if @sel_day.index==0
      @sel_hour.options=[p_("EAPI_Form", "Not selected")]
    else
      @sel_hour.options=[p_("EAPI_Form", "Not selected")]+@hours
    end
    @sel_hour.index-=1 while @sel_hour.index>=@sel_hour.options.size
              @sel_hour.trigger(:move, @sel_hour.index)
    }
    @sel_hour.on(:move) {
    if @sel_hour.index==0
      @sel_min.options=[p_("EAPI_Form", "Not selected")]
    else
      @sel_min.options=[p_("EAPI_Form", "Not selected")]+@mins
    end
    @sel_min.index-=1 while @sel_min.index>=@sel_min.options.size
              @sel_min.trigger(:move, @sel_min.index)
    }
    @sel_min.on(:move) {
    if @sel_min.index==0
      @sel_sec.options=[p_("EAPI_Form", "Not selected")]
    else
      @sel_sec.options=[p_("EAPI_Form", "Not selected")]+@mins
    end
    @sel_sec.index-=1 while @sel_sec.index>=@sel_sec.options.size
              @sel_sec.trigger(:move, @sel_sec.index)
    }
  end
  def genlabel
    @label=@dlabel+": "
    if @year==0
      @label+=p_("EAPI_Form", "Not selected")
    else
      if @includehour==false
      @label+=sprintf("%04d-%02d-%02d", @year, @month, @day)
    else
      @label+=sprintf("%04d-%02d-%02d, %02d:%02d:%02d", @year, @month, @day, @hour, @min, @sec)
      end
      end
    end
    def focus(*arg)
      genlabel
      super(*arg)
      end
  def update
    super
    if @pressed
      show
      focus
    end
  end
  def show
    @form.index=0
    @form.wait
  end
def setdate(year, month, day, hour, min, sec)
    @year, @month, @day, @hour, @min, @sec = year, month, day, hour, min, sec
genlabel
@sel_year.index=@year-@minyear+1
@sel_year.trigger(:move, @sel_year.index)
@sel_month.index=@month
@sel_month.trigger(:move, @sel_month.index)
@sel_day.index=@day
@sel_day.trigger(:move, @sel_day.index)
@sel_hour.index=@hour+1
@sel_min.index=@min+1
@sel_sec.index=@sec+1
  end
  end

  end
end
